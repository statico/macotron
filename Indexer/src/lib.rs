//! macotron-index: an in-memory file-name index with fuzzy search and
//! incremental updates. Protocol and ranking rules: docs/12-file-index.md.
//!
//! Storage: one byte arena of names (plus a lowercase copy) and a flat entry
//! table with a parent index per entry. Full paths exist only for results.

use ignore::overrides::OverrideBuilder;
use ignore::{DirEntry, WalkBuilder, WalkState};
use std::cmp::Reverse;
use std::collections::hash_map::DefaultHasher;
use std::collections::{BTreeSet, BinaryHeap, HashMap, HashSet};
use std::borrow::Cow;
use std::ffi::OsStr;
use std::hash::Hasher;
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::sync::{mpsc, OnceLock, RwLock};
use std::time::{Instant, UNIX_EPOCH};
use unicode_normalization::UnicodeNormalization;

pub const BUNDLE_EXTS: &[&str] = &[
    "app", "framework", "bundle", "xcodeproj", "xcassets", "photoslibrary",
    "musiclibrary", "tvlibrary", "playground", "lproj", "nib",
];

/// Diagnostics go to stderr only when `MACOTRON_INDEX_LOG` is set.
pub fn logging() -> bool {
    static ON: OnceLock<bool> = OnceLock::new();
    *ON.get_or_init(|| std::env::var_os("MACOTRON_INDEX_LOG").is_some())
}

#[macro_export]
macro_rules! trace {
    ($($a:tt)*) => { if $crate::logging() { eprintln!($($a)*); } };
}

pub fn is_bundle(name: &[u8]) -> bool {
    let Some(dot) = name.iter().rposition(|&b| b == b'.') else { return false };
    let ext = &name[dot + 1..];
    BUNDLE_EXTS.iter().any(|e| e.as_bytes().eq_ignore_ascii_case(ext))
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Config {
    pub roots: Vec<PathBuf>,
    pub ignore: Vec<String>,
    pub hidden: bool,
    pub ignore_files: bool,
}

impl Config {
    /// Canonicalises roots (FSEvents reports real paths, e.g. /private/tmp)
    /// and drops a root nested inside another so nothing is indexed twice.
    pub fn normalized(mut self) -> Self {
        let mut roots: Vec<PathBuf> = self
            .roots
            .iter()
            .map(|r| std::fs::canonicalize(r).unwrap_or_else(|_| r.clone()))
            .collect();
        roots.sort();
        roots.dedup();
        let mut kept: Vec<PathBuf> = Vec::new();
        for r in roots {
            if !kept.iter().any(|k| r.starts_with(k)) {
                kept.push(r);
            }
        }
        self.roots = kept;
        self
    }

    /// Rejects malformed ignore globs up front so `configure` can fail.
    pub fn check_globs(&self) -> Result<(), String> {
        let mut ov = OverrideBuilder::new("/");
        for g in &self.ignore {
            ov.add(&format!("!{g}")).map_err(|e| e.to_string())?;
        }
        Ok(())
    }
}

const NONE: u32 = u32::MAX;
const DIR: u8 = 1;
const DEAD: u8 = 2;
/// Dotted component or `Library` somewhere in the path: sorts below equals.
const LOW: u8 = 4;

#[derive(Clone, Copy)]
struct Entry {
    parent: u32,
    name: u32,  // offset into `names`; ends where the next entry's starts
    lower: u32, // offset into `lower`
    depth: u16,
    flags: u8,
}

pub struct Index {
    pub cfg: Config,
    ents: Vec<Entry>,
    names: Vec<u8>,
    lower: Vec<u8>,
    /// Which characters the lowercase name contains (see `char_bit`); a
    /// token can only match a name whose mask covers the token's mask.
    nmask: Vec<u32>,
    /// Same, for the whole path relative to the root.
    pmask: Vec<u32>,
    /// Path hash → entry. Hash is folded parent-hash + name, so a lookup
    /// never builds a full path. Verified on hit, so collisions are harmless.
    map: PathMap,
    roots: Vec<(PathBuf, u32)>,
    /// Entries not tombstoned.
    pub live: usize,
}

pub struct Query<'a> {
    pub query: &'a str,
    pub limit: usize,
    pub folder: Option<&'a Path>,
    pub kind: Option<&'a str>,
    pub dirs_only: bool,
}

#[derive(Debug)]
pub struct Hit {
    pub path: PathBuf,
    pub name: String,
    pub is_dir: bool,
    pub score: u32,
    pub modified: u32,
}

/// Path-hash table: a sorted, packed vector for everything known at build
/// time plus a small hash map for entries added since. Removed keys are left
/// in place; `lookup` rejects them through the entry's DEAD flag.
#[derive(Default)]
struct PathMap {
    sorted: Vec<(u64, u32)>,
    extra: HashMap<u64, u32>,
}

impl PathMap {
    fn get(&self, h: u64) -> Option<u32> {
        self.extra
            .get(&h)
            .copied()
            .or_else(|| self.sorted.binary_search_by_key(&h, |e| e.0).ok().map(|i| self.sorted[i].1))
    }

    fn insert(&mut self, h: u64, id: u32) {
        self.extra.insert(h, id);
    }

    /// Folds `extra` into `sorted`. Newer ids win when a hash repeats.
    fn seal(&mut self) {
        self.sorted.extend(self.extra.drain());
        self.extra.shrink_to_fit();
        self.sorted.sort_unstable();
        self.sorted.dedup_by(|later, earlier| {
            let dup = later.0 == earlier.0;
            if dup {
                earlier.1 = later.1;
            }
            dup
        });
        self.sorted.shrink_to_fit();
    }
}

fn mix(parent: u64, name: &[u8]) -> u64 {
    let mut h = DefaultHasher::new();
    h.write_u64(parent);
    h.write(name);
    h.finish()
}

fn char_bit(b: u8) -> u32 {
    match b {
        b'a'..=b'z' => 1 << (b - b'a'),
        b'0'..=b'9' => 1 << (26 + (b - b'0') % 5),
        _ => 1 << 31,
    }
}

fn mask_of(lower: &[u8]) -> u32 {
    lower.iter().fold(0, |m, &b| m | char_bit(b))
}

/// Disk names are NFD on HFS+ and whatever the writer used on APFS; queries
/// arrive NFC. Everything is compared in NFD. ASCII passes through untouched.
fn nfd(name: &[u8]) -> Cow<'_, [u8]> {
    if name.is_ascii() {
        return Cow::Borrowed(name);
    }
    match std::str::from_utf8(name) {
        Ok(s) if !unicode_normalization::is_nfd(s) => Cow::Owned(s.nfd().collect::<String>().into_bytes()),
        _ => Cow::Borrowed(name),
    }
}

pub fn mtime_of(path: &Path) -> u32 {
    std::fs::symlink_metadata(path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map_or(0, |d| d.as_secs().min(u32::MAX as u64) as u32)
}

/// Greedy subsequence advance of `tok` over `name`, starting at `st` matched
/// chars. With `sep`, a `/` in the token may match the component boundary.
fn advance(mut st: usize, tok: &[u8], name: &[u8], sep: bool) -> usize {
    if st == tok.len() {
        return st;
    }
    if sep && tok[st] == b'/' {
        st += 1;
    }
    let mut pos = 0;
    while st < tok.len() {
        match memchr::memchr(tok[st], &name[pos..]) {
            Some(p) => {
                pos += p + 1;
                st += 1;
            }
            None => break,
        }
    }
    st
}

/// Score of one token against one name (tiers 1–5); 0 when it does not match.
/// Assumes the caller has checked that every token character occurs in `lower`.
/// `fuzzy` allows tier 5 (tokens of `FUZZY_MIN`+ characters).
pub fn name_score(tok: &[u8], lower: &[u8], orig: &[u8], fuzzy: bool) -> u32 {
    if lower == tok {
        return 1000;
    }
    if lower.starts_with(tok) {
        return 900;
    }
    let same = orig.len() == lower.len();
    let mut substring = false;
    for p in memchr::memchr_iter(tok[0], lower) {
        if p == 0 || !lower[p..].starts_with(tok) {
            continue;
        }
        let boundary = matches!(lower[p - 1], b' ' | b'-' | b'_' | b'.')
            || (same && orig[p - 1].is_ascii_lowercase() && orig[p].is_ascii_uppercase());
        if boundary {
            return 800;
        }
        substring = true;
    }
    if substring {
        return 600;
    }
    if fuzzy && advance(0, tok, lower, false) == tok.len() {
        return 400;
    }
    0
}

/// Tokens shorter than this must hit tiers 1–4; subsequence tiers are off.
const FUZZY_MIN: usize = 3;

impl Index {
    pub fn new(cfg: Config) -> Self {
        Index {
            cfg,
            ents: Vec::new(),
            names: Vec::new(),
            lower: Vec::new(),
            nmask: Vec::new(),
            pmask: Vec::new(),
            map: PathMap::default(),
            roots: Vec::new(),
            live: 0,
        }
    }

    pub fn len(&self) -> usize {
        self.live
    }

    pub fn is_empty(&self) -> bool {
        self.live == 0
    }

    /// Bytes held by the arenas and tables (excludes allocator overhead).
    pub fn heap_bytes(&self) -> usize {
        self.ents.capacity() * std::mem::size_of::<Entry>()
            + self.names.capacity()
            + self.lower.capacity()
            + (self.nmask.capacity() + self.pmask.capacity()) * 4
            + self.map.sorted.capacity() * 12
            + self.map.extra.capacity() * 16
    }

    fn name(&self, i: u32) -> &[u8] {
        let s = self.ents[i as usize].name as usize;
        let e = self.ents.get(i as usize + 1).map_or(self.names.len(), |n| n.name as usize);
        &self.names[s..e]
    }

    fn lower(&self, i: u32) -> &[u8] {
        let s = self.ents[i as usize].lower as usize;
        let e = self.ents.get(i as usize + 1).map_or(self.lower.len(), |n| n.lower as usize);
        &self.lower[s..e]
    }

    pub fn is_dir(&self, i: u32) -> bool {
        self.ents[i as usize].flags & DIR != 0
    }

    pub fn path(&self, i: u32) -> PathBuf {
        let mut parts = Vec::new();
        let mut j = i;
        loop {
            parts.push(self.name(j));
            let p = self.ents[j as usize].parent;
            if p == NONE {
                break;
            }
            j = p;
        }
        let mut buf = Vec::with_capacity(parts.iter().map(|p| p.len() + 1).sum());
        for (k, part) in parts.iter().rev().enumerate() {
            if k > 0 {
                buf.push(b'/');
            }
            buf.extend_from_slice(part);
        }
        PathBuf::from(OsStr::from_bytes(&buf))
    }

    fn root_path(&self, mut id: u32) -> &Path {
        while self.ents[id as usize].parent != NONE {
            id = self.ents[id as usize].parent;
        }
        &self.roots.iter().find(|(_, r)| *r == id).expect("root entry").0
    }

    fn push(&mut self, parent: u32, parent_hash: u64, name: &[u8], is_dir: bool) -> (u32, u64) {
        let name = &*nfd(name);
        let id = self.ents.len() as u32;
        let (depth, mut flags, pmask) = if parent == NONE {
            (Path::new(OsStr::from_bytes(name)).components().count() as u16, 0, 0)
        } else {
            let p = self.ents[parent as usize];
            (p.depth.saturating_add(1), p.flags & LOW, self.pmask[parent as usize] | char_bit(b'/'))
        };
        if is_dir {
            flags |= DIR;
        }
        if parent != NONE && (name.starts_with(b".") || name == b"Library") {
            flags |= LOW;
        }
        let h = mix(parent_hash, name);
        self.ents.push(Entry { parent, name: self.names.len() as u32, lower: self.lower.len() as u32, depth, flags });
        self.names.extend_from_slice(name);
        let start = self.lower.len();
        if name.is_ascii() {
            self.lower.extend(name.iter().map(u8::to_ascii_lowercase));
        } else if let Ok(s) = std::str::from_utf8(name) {
            self.lower.extend_from_slice(s.to_lowercase().as_bytes());
        } else {
            self.lower.extend_from_slice(name);
        }
        let nmask = if parent == NONE { 0 } else { mask_of(&self.lower[start..]) };
        self.nmask.push(nmask);
        self.pmask.push(pmask | nmask);
        self.map.insert(h, id);
        self.live += 1;
        (id, h)
    }

    /// Entry id and path hash for an absolute path, if indexed and alive.
    pub fn lookup(&self, path: &Path) -> Option<(u32, u64)> {
        let (root, rid) = self.roots.iter().find(|(r, _)| path.starts_with(r))?;
        let mut id = *rid;
        let mut h = mix(0, root.as_os_str().as_bytes());
        for c in path.strip_prefix(root).ok()?.components() {
            let name = &*nfd(c.as_os_str().as_bytes());
            h = mix(h, name);
            let cid = self.map.get(h)?;
            let e = &self.ents[cid as usize];
            if e.parent != id || self.name(cid) != name {
                return None;
            }
            id = cid;
        }
        (self.ents[id as usize].flags & DEAD == 0).then_some((id, h))
    }

    /// Tombstones an entry. Its path-map key stays; `lookup` rejects DEAD
    /// entries and a re-created path lands in `map.extra`, checked first.
    fn remove(&mut self, id: u32) {
        let e = &mut self.ents[id as usize];
        if e.flags & DEAD == 0 {
            e.flags |= DEAD;
            self.live -= 1;
        }
    }

    /// Tombstones live children of each listed directory whose exact (NFD)
    /// name is absent from that directory's fresh listing.
    fn remove_missing_children(&mut self, listings: &HashMap<u32, HashSet<Vec<u8>>>) {
        for i in 0..self.ents.len() {
            let e = self.ents[i];
            if e.flags & DEAD != 0 || e.parent == NONE {
                continue;
            }
            if let Some(names) = listings.get(&e.parent) {
                if !names.contains(self.name(i as u32)) {
                    self.remove(i as u32);
                }
            }
        }
    }

    /// Tombstones every descendant of a tombstoned entry. Entries are stored
    /// parents-first, so one forward pass suffices.
    fn propagate_dead(&mut self) {
        for i in 0..self.ents.len() {
            let p = self.ents[i].parent;
            if p != NONE && self.ents[p as usize].flags & DEAD != 0 && self.ents[i].flags & DEAD == 0 {
                self.ents[i].flags |= DEAD;
                self.live -= 1;
            }
        }
    }

    /// Full walk of every root. Inserts stream in while the walk runs, so
    /// nothing bigger than a chunk of entries is ever held aside.
    pub fn build(cfg: &Config) -> Index {
        let mut idx = Index::new(cfg.clone());
        for root in &cfg.roots {
            let Ok(meta) = std::fs::symlink_metadata(root) else {
                trace!("root missing: {}", root.display());
                continue;
            };
            let (rid, _) = idx.push(NONE, 0, root.as_os_str().as_bytes(), meta.is_dir());
            idx.roots.push((root.clone(), rid));
            let t = Instant::now();
            let before = idx.ents.len();
            let (tx, rx) = mpsc::channel();
            std::thread::scope(|s| {
                s.spawn(|| walk(cfg, root, root, None, tx));
                for mut chunk in rx {
                    chunk.retain(|r| r.depth > 0);
                    sort_raws(&mut chunk);
                    idx.insert_raws(chunk, false);
                }
            });
            trace!("walked {}: {} entries in {:?}", root.display(), idx.ents.len() - before, t.elapsed());
        }
        idx.ents.shrink_to_fit();
        idx.names.shrink_to_fit();
        idx.lower.shrink_to_fit();
        idx.map.seal();
        idx
    }

    /// Inserts walked entries. `raws` must be sorted by path so parents come
    /// first. With `check`, entries already present are skipped.
    fn insert_raws(&mut self, raws: Vec<Raw>, check: bool) {
        let mut cache: Option<(PathBuf, u32, u64)> = None;
        for raw in raws {
            if check && self.lookup(&raw.path).is_some() {
                continue;
            }
            let (Some(parent), Some(name)) = (raw.path.parent(), raw.path.file_name()) else { continue };
            let (pid, ph) = match &cache {
                Some((p, id, h)) if p == parent => (*id, *h),
                _ => match self.lookup(parent) {
                    Some(x) => {
                        cache = Some((parent.to_path_buf(), x.0, x.1));
                        x
                    }
                    None => {
                        trace!("orphan: {}", raw.path.display());
                        continue;
                    }
                },
            };
            self.push(pid, ph, name.as_bytes(), raw.is_dir);
        }
    }

    fn folder_mask(&self, folder: &Path) -> Vec<bool> {
        let folder = std::fs::canonicalize(folder).unwrap_or_else(|_| folder.to_path_buf());
        let fid = self.lookup(&folder).map(|(id, _)| id);
        let mut m = vec![false; self.ents.len()];
        for i in 0..self.ents.len() {
            let e = &self.ents[i];
            m[i] = if fid == Some(i as u32) {
                true
            } else if e.parent == NONE {
                self.roots.iter().any(|(r, id)| *id == i as u32 && r.starts_with(&folder))
            } else {
                m[e.parent as usize]
            };
        }
        m
    }

    /// How much of `tok` the path relative to the root (through entry `i`)
    /// matches as a subsequence. Memoised in `state` (UNSET = not yet known);
    /// climbs to the nearest known ancestor and fills in downwards.
    fn path_state(&self, i: usize, tok: &[u8], state: &mut [u16], stack: &mut Vec<usize>) -> usize {
        const UNSET: u16 = u16::MAX;
        let mut j = i;
        while state[j] == UNSET {
            stack.push(j);
            let p = self.ents[j].parent;
            if p == NONE {
                state[j] = 0;
                break;
            }
            j = p as usize;
        }
        while let Some(k) = stack.pop() {
            let p = self.ents[k].parent;
            state[k] = if p == NONE { 0 } else { advance(state[p as usize] as usize, tok, self.lower(k as u32), true) as u16 };
        }
        state[i] as usize
    }

    pub fn search(&self, q: &Query) -> Vec<Hit> {
        let lowered = q.query.nfd().collect::<String>().to_lowercase();
        // (token bytes, fuzzy tiers allowed)
        let tokens: Vec<(&[u8], bool)> =
            lowered.split_whitespace().map(|t| (t.as_bytes(), t.chars().count() >= FUZZY_MIN)).collect();
        if tokens.is_empty() || q.limit == 0 || tokens.iter().any(|(t, _)| t.len() >= u16::MAX as usize) {
            return Vec::new();
        }
        let n = self.ents.len();
        const OUT: u32 = u32::MAX;
        let kind = q.kind.map(|k| format!(".{}", k.to_lowercase()).into_bytes());
        let folder = q.folder.map(|f| self.folder_mask(f));
        let mut score = vec![0u32; n];
        for (i, e) in self.ents.iter().enumerate() {
            let out = e.flags & DEAD != 0
                || e.parent == NONE // roots are containers, not results
                || (q.dirs_only && e.flags & DIR == 0)
                || kind.as_ref().is_some_and(|k| {
                    let l = self.lower(i as u32);
                    l.len() <= k.len() || !l.ends_with(k)
                })
                || folder.as_ref().is_some_and(|m| !m[i]);
            if out {
                score[i] = OUT;
            }
        }
        let mut state = vec![u16::MAX; n];
        let mut stack = Vec::new();
        // Multi-token: at least one token must hit the name at tier 4+.
        let mut strong = vec![tokens.len() == 1; n];
        for &(tok, fuzzy) in &tokens {
            let tmask = mask_of(tok);
            state.fill(u16::MAX);
            for (i, sc) in score.iter_mut().enumerate() {
                if *sc == OUT {
                    continue;
                }
                let mut s = 0;
                if self.nmask[i] & tmask == tmask {
                    s = name_score(tok, self.lower(i as u32), self.name(i as u32), fuzzy);
                }
                if s == 0
                    && fuzzy
                    && self.pmask[i] & tmask == tmask
                    && self.path_state(i, tok, &mut state, &mut stack) == tok.len()
                {
                    s = 200;
                }
                if s == 0 {
                    *sc = OUT;
                } else {
                    *sc += s;
                    strong[i] |= s >= 600;
                }
            }
        }
        for (sc, strong) in score.iter_mut().zip(&strong) {
            if !strong {
                *sc = OUT;
            }
        }
        // Best `limit` by (score, not LOW, shallow, short name, path order).
        let mut heap = BinaryHeap::with_capacity(q.limit + 1);
        for (i, e) in self.ents.iter().enumerate() {
            if score[i] == OUT {
                continue;
            }
            let key = Reverse((score[i], e.flags & LOW == 0, Reverse(e.depth), Reverse(self.name(i as u32).len()), Reverse(i)));
            if heap.len() < q.limit {
                heap.push(key);
            } else if key < *heap.peek().unwrap() {
                heap.pop();
                heap.push(key);
            }
        }
        let mut keys: Vec<_> = heap.into_iter().map(|r| r.0).collect();
        keys.sort_unstable_by(|a, b| b.cmp(a));
        keys.into_iter()
            .map(|(score, _, _, _, Reverse(i))| {
                let i = i as u32;
                Hit {
                    modified: 0, // callers stat outside the lock (`mtime_of`)
                    path: self.path(i),
                    name: String::from_utf8_lossy(self.name(i)).into_owned(),
                    is_dir: self.is_dir(i),
                    score,
                }
            })
            .collect()
    }
}

struct Raw {
    path: PathBuf,
    is_dir: bool,
    depth: usize,
}

fn sort_raws(raws: &mut [Raw]) {
    raws.sort_unstable_by(|a, b| a.path.as_os_str().as_bytes().cmp(b.path.as_os_str().as_bytes()));
}

/// A walker over `from` with the ignore rules of `root` (the configured root
/// that contains it), so relative globs like `Library/Caches` line up.
fn walker(cfg: &Config, root: &Path, from: &Path) -> Result<WalkBuilder, ignore::Error> {
    let mut b = WalkBuilder::new(from);
    b.hidden(!cfg.hidden)
        .follow_links(false)
        .git_global(false)
        .git_exclude(false)
        .require_git(false)
        .git_ignore(cfg.ignore_files)
        .ignore(cfg.ignore_files)
        .parents(cfg.ignore_files);
    if cfg.ignore_files {
        b.add_custom_ignore_filename(".macotronignore");
    }
    let mut ov = OverrideBuilder::new(root);
    for g in &cfg.ignore {
        ov.add(&format!("!{g}"))?;
    }
    b.overrides(ov.build()?);
    Ok(b)
}

/// Per-thread collector. A chunk is sent as soon as it holds a directory, and
/// the walker only descends after `visit` returns, so every chunk reaches the
/// channel before any chunk holding that directory's children.
struct Visitor {
    buf: Vec<Raw>,
    tx: mpsc::Sender<Vec<Raw>>,
}

impl Visitor {
    fn flush(&mut self) {
        if !self.buf.is_empty() {
            let _ = self.tx.send(std::mem::take(&mut self.buf));
        }
    }
}

impl ignore::ParallelVisitor for Visitor {
    fn visit(&mut self, entry: Result<DirEntry, ignore::Error>) -> WalkState {
        let e = match entry {
            Ok(e) => e,
            Err(err) => {
                trace!("walk: {err}");
                return WalkState::Continue;
            }
        };
        let is_dir = e.file_type().is_some_and(|t| t.is_dir());
        let bundle = is_dir && is_bundle(e.file_name().as_bytes());
        let depth = e.depth();
        self.buf.push(Raw { path: e.into_path(), is_dir, depth });
        if is_dir || self.buf.len() >= 1024 {
            self.flush();
        }
        if bundle { WalkState::Skip } else { WalkState::Continue }
    }
}

impl Drop for Visitor {
    fn drop(&mut self) {
        self.flush();
    }
}

struct Builder(mpsc::Sender<Vec<Raw>>);

impl<'s> ignore::ParallelVisitorBuilder<'s> for Builder {
    fn build(&mut self) -> Box<dyn ignore::ParallelVisitor + 's> {
        Box::new(Visitor { buf: Vec::new(), tx: self.0.clone() })
    }
}

fn walk(cfg: &Config, root: &Path, from: &Path, max_depth: Option<usize>, tx: mpsc::Sender<Vec<Raw>>) {
    let mut b = match walker(cfg, root, from) {
        Ok(b) => b,
        Err(e) => {
            trace!("ignore rules: {e}");
            return;
        }
    };
    b.max_depth(max_depth);
    b.build_parallel().visit(&mut Builder(tx));
}

fn collect(cfg: &Config, root: &Path, from: &Path, max_depth: Option<usize>) -> Vec<Raw> {
    let (tx, rx) = mpsc::channel();
    walk(cfg, root, from, max_depth, tx);
    let mut raws: Vec<Raw> = rx.into_iter().flatten().collect();
    sort_raws(&mut raws);
    raws
}

/// Applies a batch of changed paths: re-stats each, removes what is gone,
/// re-lists the parent of anything present (so ignore rules and bundles apply
/// to new entries exactly as in a full walk) and walks new directories.
/// Filesystem work happens outside the lock; the lock is held only to mutate.
pub fn apply(index: &RwLock<Index>, paths: HashSet<PathBuf>) {
    let cfg = index.read().unwrap_or_else(|e| e.into_inner()).cfg.clone();
    let mut removals = Vec::new();
    let mut resync = BTreeSet::new();
    {
        let idx = index.read().unwrap_or_else(|e| e.into_inner());
        for p in paths {
            match std::fs::symlink_metadata(&p) {
                Err(_) => {
                    if idx.lookup(&p).is_some() {
                        removals.push(p);
                    }
                }
                Ok(m) => {
                    if let Some((id, _)) = idx.lookup(&p) {
                        if idx.is_dir(id) != m.is_dir() {
                            removals.push(p.clone());
                        }
                    }
                    if let Some(parent) = p.parent() {
                        resync.insert(parent.to_path_buf());
                    }
                    if m.is_dir() {
                        resync.insert(p);
                    }
                }
            }
        }
    }
    if !removals.is_empty() {
        let mut w = index.write().unwrap_or_else(|e| e.into_inner());
        for p in &removals {
            if let Some((id, _)) = w.lookup(p) {
                trace!("removed {}", p.display());
                w.remove(id);
            }
        }
        w.propagate_dead();
    }
    // Fresh depth-1 listings, taken without the lock.
    let mut listings: Vec<(u32, PathBuf, Vec<Raw>)> = Vec::new();
    for dir in resync {
        let (id, root) = {
            let idx = index.read().unwrap_or_else(|e| e.into_inner());
            let Some((id, _)) = idx.lookup(&dir) else { continue };
            if !idx.is_dir(id) || is_bundle(idx.name(id)) {
                continue;
            }
            (id, idx.root_path(id).to_path_buf())
        };
        let mut raws = collect(&cfg, &root, &dir, Some(1));
        raws.retain(|r| r.depth > 0);
        listings.push((id, root, raws));
    }
    if listings.is_empty() {
        return;
    }
    // One write pass: drop children no longer listed, then add the new ones.
    let deep: Vec<(PathBuf, PathBuf)> = {
        let mut w = index.write().unwrap_or_else(|e| e.into_inner());
        let names = listings
            .iter()
            .map(|(id, _, raws)| (*id, raws.iter().filter_map(|r| r.path.file_name()).map(|n| nfd(n.as_bytes()).into_owned()).collect()))
            .collect();
        w.remove_missing_children(&names);
        w.propagate_dead();
        let mut deep = Vec::new();
        for (_, root, raws) in listings {
            for r in &raws {
                if r.is_dir && w.lookup(&r.path).is_none() && !r.path.file_name().is_some_and(|n| is_bundle(n.as_bytes())) {
                    deep.push((root.clone(), r.path.clone()));
                }
            }
            w.insert_raws(raws, true);
        }
        deep
    };
    for (root, d) in deep {
        trace!("new dir {}", d.display());
        let raws = collect(&cfg, &root, &d, None);
        index.write().unwrap_or_else(|e| e.into_inner()).insert_raws(raws, true);
    }
}

/// Resident set size of this process, from `mach_task_basic_info`.
#[allow(deprecated)] // libc points at the mach2 crate; not worth a dependency
pub fn resident_bytes() -> u64 {
    let mut info: libc::mach_task_basic_info = unsafe { std::mem::zeroed() };
    let mut count = libc::MACH_TASK_BASIC_INFO_COUNT;
    // SAFETY: plain mach call with a correctly sized out-buffer.
    let kr = unsafe {
        libc::task_info(
            libc::mach_task_self_,
            libc::MACH_TASK_BASIC_INFO,
            &mut info as *mut _ as libc::task_info_t,
            &mut count,
        )
    };
    if kr == libc::KERN_SUCCESS { info.resident_size } else { 0 }
}
