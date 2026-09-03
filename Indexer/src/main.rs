//! Newline-delimited JSON over stdin/stdout. See docs/12-file-index.md.

use macotron_index::{apply, mtime_of, trace, Config, Hit, Index, Query};
use notify::{RecursiveMode, Watcher};
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::HashSet;
use std::io::{self, BufRead, Write};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering::SeqCst};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::sync::{Arc, Mutex, RwLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const QUIET: Duration = Duration::from_millis(500);
const MAX_BURST: Duration = Duration::from_secs(5);
const REWALK_ABOVE: usize = 10_000;

fn yes() -> bool {
    true
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Request {
    id: Option<Value>,
    op: String,
    #[serde(default)]
    roots: Vec<String>,
    #[serde(default)]
    ignore: Vec<String>,
    #[serde(default)]
    hidden: bool,
    #[serde(default = "yes")]
    ignore_files: bool,
    #[serde(default)]
    query: String,
    limit: Option<i64>,
    folder: Option<String>,
    kind: Option<String>,
    #[serde(default)]
    dirs_only: bool,
}

struct Shared {
    index: RwLock<Index>,
    cfg: Mutex<Option<Config>>,
    /// Bumped by every configure/reindex; a build whose gen is stale is dropped.
    gen: AtomicU64,
    indexing: AtomicBool,
    watching: AtomicBool,
    last_indexed: AtomicU64,
}

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs())
}

fn start_build(shared: &Arc<Shared>, cfg: Config) {
    let gen = shared.gen.fetch_add(1, SeqCst) + 1;
    shared.indexing.store(true, SeqCst);
    shared.watching.store(false, SeqCst);
    let shared = shared.clone();
    std::thread::spawn(move || run(shared, cfg, gen));
}

/// Builds the index, swaps it in, then watches the roots until superseded.
/// The watcher starts before the walk so nothing changed mid-walk is missed.
fn run(shared: Arc<Shared>, cfg: Config, gen: u64) {
    let (tx, rx) = mpsc::channel();
    let mut watcher = notify::recommended_watcher(move |r| {
        let _ = tx.send(r);
    })
    .map_err(|e| trace!("watcher: {e}"))
    .ok();
    let mut watching = watcher.is_some();
    if let Some(w) = &mut watcher {
        for r in &cfg.roots {
            if let Err(e) = w.watch(r, RecursiveMode::Recursive) {
                trace!("watch {}: {e}", r.display());
                watching = false;
            }
        }
    }
    let t = Instant::now();
    let idx = Index::build(&cfg);
    trace!("built {} entries in {:?}, rss {} MB", idx.len(), t.elapsed(), macotron_index::resident_bytes() >> 20);
    {
        // Lock first: a newer build that already landed must not be overwritten.
        let mut w = shared.index.write().unwrap_or_else(|e| e.into_inner());
        if shared.gen.load(SeqCst) != gen {
            return;
        }
        *w = idx;
    }
    shared.last_indexed.store(now(), SeqCst);
    shared.indexing.store(false, SeqCst);
    shared.watching.store(watching, SeqCst);
    if watcher.is_none() {
        return;
    }
    loop {
        if shared.gen.load(SeqCst) != gen {
            return;
        }
        let first = match rx.recv_timeout(Duration::from_secs(1)) {
            Ok(ev) => ev,
            Err(RecvTimeoutError::Timeout) => continue,
            Err(RecvTimeoutError::Disconnected) => return,
        };
        let mut paths = HashSet::new();
        let mut rescan = false;
        let started = Instant::now();
        let mut absorb = |ev: notify::Result<notify::Event>, paths: &mut HashSet<PathBuf>| match ev {
            Ok(ev) => {
                rescan |= ev.need_rescan();
                paths.extend(ev.paths);
            }
            Err(e) => trace!("fsevents: {e}"),
        };
        absorb(first, &mut paths);
        while started.elapsed() < MAX_BURST && paths.len() <= REWALK_ABOVE {
            match rx.recv_timeout(QUIET) {
                Ok(ev) => absorb(ev, &mut paths),
                Err(_) => break,
            }
        }
        if rescan || paths.len() > REWALK_ABOVE {
            trace!("rewalk: rescan={rescan} paths={}", paths.len());
            if shared.gen.load(SeqCst) == gen {
                start_build(&shared, cfg);
            }
            return;
        }
        let t = Instant::now();
        let n = paths.len();
        apply(&shared.index, paths);
        trace!("applied {n} changes in {:?}", t.elapsed());
    }
}

fn hit_json(h: &Hit) -> Value {
    json!({
        "path": h.path.to_string_lossy(),
        "name": h.name,
        "isDir": h.is_dir,
        "score": h.score,
        "modified": h.modified,
    })
}

fn handle(req: Request, shared: &Arc<Shared>) -> Value {
    let id = req.id.clone().unwrap_or(Value::Null);
    match req.op.as_str() {
        "configure" => {
            let cfg = Config {
                roots: req.roots.iter().map(PathBuf::from).collect(),
                ignore: req.ignore,
                hidden: req.hidden,
                ignore_files: req.ignore_files,
            }
            .normalized();
            if let Err(e) = cfg.check_globs() {
                return json!({"id": id, "ok": false, "error": e});
            }
            let mut cur = shared.cfg.lock().unwrap_or_else(|e| e.into_inner());
            if cur.as_ref() != Some(&cfg) {
                *cur = Some(cfg.clone());
                start_build(shared, cfg);
            }
            json!({"id": id, "ok": true})
        }
        "search" => {
            let limit = req.limit.unwrap_or(50).clamp(1, 500) as usize;
            let q = Query {
                query: &req.query,
                limit,
                folder: req.folder.as_deref().map(std::path::Path::new),
                kind: req.kind.as_deref(),
                dirs_only: req.dirs_only,
            };
            let mut hits = shared.index.read().unwrap_or_else(|e| e.into_inner()).search(&q);
            for h in &mut hits {
                h.modified = mtime_of(&h.path); // stat outside the lock
            }
            json!({
                "id": id, "ok": true,
                "indexing": shared.indexing.load(SeqCst),
                "results": hits.iter().map(hit_json).collect::<Vec<_>>(),
            })
        }
        "status" => {
            let idx = shared.index.read().unwrap_or_else(|e| e.into_inner());
            let roots: Vec<String> = idx.cfg.roots.iter().map(|r| r.to_string_lossy().into_owned()).collect();
            json!({
                "id": id, "ok": true,
                "entries": idx.len(),
                "indexing": shared.indexing.load(SeqCst),
                "watching": shared.watching.load(SeqCst),
                "roots": roots,
                "lastIndexed": shared.last_indexed.load(SeqCst),
                "memoryBytes": macotron_index::resident_bytes(),
            })
        }
        "reindex" => {
            let cfg = shared.cfg.lock().unwrap_or_else(|e| e.into_inner()).clone();
            match cfg {
                Some(cfg) => {
                    start_build(shared, cfg);
                    json!({"id": id, "ok": true})
                }
                None => json!({"id": id, "ok": false, "error": "not configured"}),
            }
        }
        "shutdown" => json!({"id": id, "ok": true}),
        other => json!({"id": id, "ok": false, "error": format!("unknown op: {other}")}),
    }
}

fn main() {
    let shared = Arc::new(Shared {
        index: RwLock::new(Index::new(Config::default())),
        cfg: Mutex::new(None),
        gen: AtomicU64::new(0),
        indexing: AtomicBool::new(false),
        watching: AtomicBool::new(false),
        last_indexed: AtomicU64::new(0),
    });
    let mut stdin = io::stdin().lock();
    let mut out = io::stdout().lock();
    let mut line = Vec::new();
    loop {
        line.clear();
        match stdin.read_until(b'\n', &mut line) {
            Ok(0) | Err(_) => break,
            Ok(_) => {}
        }
        if line.iter().all(u8::is_ascii_whitespace) {
            continue;
        }
        // Parse as a Value first so the error can still echo the id.
        let (resp, quit) = match serde_json::from_slice::<Value>(&line) {
            Ok(v) => {
                let id = v.get("id").cloned().unwrap_or(Value::Null);
                match serde_json::from_value::<Request>(v) {
                    Ok(req) => {
                        let quit = req.op == "shutdown";
                        (handle(req, &shared), quit)
                    }
                    Err(e) => (json!({"id": id, "ok": false, "error": format!("bad request: {e}")}), false),
                }
            }
            Err(e) => (json!({"id": null, "ok": false, "error": format!("bad request: {e}")}), false),
        };
        let _ = writeln!(out, "{resp}");
        let _ = out.flush();
        if quit {
            break;
        }
    }
    std::process::exit(0);
}
