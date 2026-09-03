use macotron_index::{apply, Config, Index, Query};
use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::RwLock;

/// Creates files; a path ending in `/` is a directory.
fn tree(root: &Path, paths: &[&str]) {
    for p in paths {
        let full = root.join(p);
        if p.ends_with('/') {
            fs::create_dir_all(&full).unwrap();
        } else {
            fs::create_dir_all(full.parent().unwrap()).unwrap();
            fs::write(&full, "x").unwrap();
        }
    }
}

fn cfg(root: &Path) -> Config {
    Config { roots: vec![root.to_path_buf()], ignore: vec![], hidden: false, ignore_files: true }.normalized()
}

fn names(idx: &Index, q: &str) -> Vec<String> {
    idx.search(&Query { query: q, limit: 50, folder: None, kind: None, dirs_only: false })
        .into_iter()
        .map(|h| h.name)
        .collect()
}

fn rel(idx: &Index, q: &str) -> Vec<String> {
    let root = idx.cfg.roots[0].clone();
    idx.search(&Query { query: q, limit: 50, folder: None, kind: None, dirs_only: false })
        .into_iter()
        .map(|h| h.path.strip_prefix(&root).unwrap().to_string_lossy().into_owned())
        .collect()
}

#[test]
fn ignore_globs_name_and_relative_forms() {
    let t = tempfile::tempdir().unwrap();
    tree(t.path(), &["proj/node_modules/x.js", "proj/src/x.js", "a.tmp", "Library/Caches/c.txt", "other/Library/Caches/d.txt"]);
    let c = Config { ignore: vec!["node_modules".into(), "*.tmp".into(), "Library/Caches".into()], ..cfg(t.path()) };
    let idx = Index::build(&c);
    assert_eq!(rel(&idx, "x.js"), vec!["proj/src/x.js"]);
    assert!(names(&idx, "a.tmp").is_empty());
    assert!(names(&idx, "node_modules").is_empty());
    assert_eq!(rel(&idx, "txt"), vec!["other/Library/Caches/d.txt"]);
}

#[test]
fn hidden_flag() {
    let t = tempfile::tempdir().unwrap();
    tree(t.path(), &[".dotfile", ".dotdir/inner.txt", "plain.txt"]);
    let idx = Index::build(&cfg(t.path()));
    assert!(names(&idx, "dot").is_empty());
    assert!(names(&idx, "inner").is_empty());
    let idx = Index::build(&Config { hidden: true, ..cfg(t.path()) });
    assert_eq!(names(&idx, "dotfile"), vec![".dotfile"]);
    assert_eq!(names(&idx, "inner"), vec!["inner.txt"]);
}

#[test]
fn ignore_files_only_when_enabled() {
    let t = tempfile::tempdir().unwrap();
    tree(t.path(), &["secret.txt", "sub/scratch.txt", "keep.txt"]);
    fs::write(t.path().join(".gitignore"), "secret.txt\n").unwrap();
    fs::write(t.path().join("sub/.macotronignore"), "scratch.txt\n").unwrap();
    let idx = Index::build(&cfg(t.path()));
    assert_eq!(names(&idx, "txt"), vec!["keep.txt"]);
    let idx = Index::build(&Config { ignore_files: false, ..cfg(t.path()) });
    assert_eq!(names(&idx, "txt").len(), 3);
}

#[test]
fn bundles_are_single_entries() {
    let t = tempfile::tempdir().unwrap();
    tree(t.path(), &["Apps/Foo.app/Contents/MacOS/foo", "Proj.xcodeproj/project.pbxproj", "plain/foo.txt"]);
    let idx = Index::build(&cfg(t.path()));
    let hits = idx.search(&Query { query: "foo", limit: 50, folder: None, kind: None, dirs_only: false });
    let got: Vec<(String, bool)> = hits.iter().map(|h| (h.name.clone(), h.is_dir)).collect();
    assert_eq!(got, vec![("Foo.app".to_string(), true), ("foo.txt".to_string(), false)]);
    assert!(names(&idx, "pbxproj").is_empty());
    assert_eq!(names(&idx, "proj"), vec!["Proj.xcodeproj"]);
}

#[test]
fn ranking_tiers_in_order() {
    let t = tempfile::tempdir().unwrap();
    tree(t.path(), &["budget", "budget-2024.pdf", "Q3 Budget.pdf", "myBudget.txt", "overbudget.txt", "bxuxdxgxext", "bud/get", "nomatch.txt"]);
    let idx = Index::build(&cfg(t.path()));
    let hits = idx.search(&Query { query: "budget", limit: 50, folder: None, kind: None, dirs_only: false });
    let got: Vec<(String, u32)> = hits.iter().map(|h| (h.name.clone(), h.score)).collect();
    assert_eq!(
        got,
        vec![
            ("budget".to_string(), 1000),
            ("budget-2024.pdf".to_string(), 900),
            ("myBudget.txt".to_string(), 800),
            ("Q3 Budget.pdf".to_string(), 800),
            ("overbudget.txt".to_string(), 600),
            ("bxuxdxgxext".to_string(), 400),
            ("get".to_string(), 200),
        ]
    );
    assert_eq!(rel(&idx, "docdad"), Vec::<String>::new());
}

#[test]
fn path_subsequence_and_tiebreaks() {
    let t = tempfile::tempdir().unwrap();
    tree(t.path(), &["Documents/Dad", "deep/er/conf.txt", "a/conf.txt", "Library/conf.txt", "a/conf-long.txt"]);
    let idx = Index::build(&cfg(t.path()));
    assert_eq!(rel(&idx, "docdad"), vec!["Documents/Dad"]);
    // all prefix hits: shallower first, shorter name next, Library below equals.
    assert_eq!(rel(&idx, "conf"), vec!["a/conf.txt", "a/conf-long.txt", "deep/er/conf.txt", "Library/conf.txt"]);
    tree(t.path(), &[".dot/conf.txt"]);
    let idx = Index::build(&Config { hidden: true, ..cfg(t.path()) });
    let got = rel(&idx, "conf");
    assert_eq!(got[..3], ["a/conf.txt".to_string(), "a/conf-long.txt".to_string(), "deep/er/conf.txt".to_string()]);
    let mut low = got[3..].to_vec();
    low.sort(); // full ties between directories keep walk order, which is not stable
    assert_eq!(low, vec![".dot/conf.txt", "Library/conf.txt"]);
}

#[test]
fn multi_token_all_must_match() {
    let t = tempfile::tempdir().unwrap();
    tree(t.path(), &["Q3 Budget.pdf", "budget-2024.pdf", "q3-notes.txt"]);
    let idx = Index::build(&cfg(t.path()));
    let hits = idx.search(&Query { query: "q3 bud", limit: 50, folder: None, kind: None, dirs_only: false });
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].name, "Q3 Budget.pdf");
    assert_eq!(hits[0].score, 900 + 800);
    assert!(names(&idx, "").is_empty());
    assert_eq!(names(&idx, "BUDGET").len(), 2);
}

#[test]
fn short_tokens_and_fuzzy_only_queries_do_not_match() {
    let t = tempfile::tempdir().unwrap();
    tree(t.path(), &["qx3/arm_biquad.c", "Q3 Budget.pdf", "Documents/Dad"]);
    let idx = Index::build(&cfg(t.path()));
    // "q3" is a path subsequence and "bud" a name subsequence of biquad: neither counts.
    assert_eq!(names(&idx, "q3 bud"), vec!["Q3 Budget.pdf"]);
    // A two-character token needs tiers 1–4 on the name.
    assert_eq!(names(&idx, "q3"), vec!["Q3 Budget.pdf"]);
    assert!(names(&idx, "bq").is_empty());
    assert_eq!(names(&idx, "bqd").len(), 1);
    // Single fuzzy tokens still work; two fuzzy tokens together do not.
    assert_eq!(rel(&idx, "docdad"), vec!["Documents/Dad"]);
    assert!(names(&idx, "docdad bqd").is_empty());
    assert_eq!(names(&idx, "dad docdad"), vec!["Dad"]);
}

#[test]
fn filters() {
    let t = tempfile::tempdir().unwrap();
    tree(t.path(), &["docs/report.PDF", "docs/report.txt", "docs-old/report.pdf", "docs/reports/"]);
    let idx = Index::build(&cfg(t.path()));
    let q = |folder: Option<&Path>, kind: Option<&str>, dirs_only: bool| {
        idx.search(&Query { query: "report", limit: 50, folder, kind, dirs_only })
            .into_iter()
            .map(|h| h.path.strip_prefix(t.path().canonicalize().unwrap()).unwrap().to_string_lossy().into_owned())
            .collect::<Vec<_>>()
    };
    let mut pdfs = q(None, Some("pdf"), false);
    pdfs.sort();
    assert_eq!(pdfs, vec!["docs-old/report.pdf", "docs/report.PDF"]);
    let docs = q(Some(&t.path().join("docs")), None, false);
    assert_eq!(docs.len(), 3);
    assert!(docs.iter().all(|p| p.starts_with("docs/")));
    assert_eq!(q(None, None, true), vec!["docs/reports"]);
    assert!(q(Some(Path::new("/nonexistent")), None, false).is_empty());
    assert_eq!(q(Some(Path::new("/")), None, false).len(), 4);
}

#[test]
fn symlinks_not_followed() {
    let t = tempfile::tempdir().unwrap();
    tree(t.path(), &["target/inside.txt"]);
    std::os::unix::fs::symlink(t.path().join("target"), t.path().join("link")).unwrap();
    let idx = Index::build(&cfg(t.path()));
    assert_eq!(rel(&idx, "inside"), vec!["target/inside.txt"]);
    let hits = idx.search(&Query { query: "link", limit: 50, folder: None, kind: None, dirs_only: false });
    assert_eq!(hits.len(), 1);
    assert!(!hits[0].is_dir);
}

#[test]
fn incremental_apply() {
    let t = tempfile::tempdir().unwrap();
    tree(t.path(), &["a/one.txt", "proj/src/x.js"]);
    let c = Config { ignore: vec!["node_modules".into()], ..cfg(t.path()) };
    let root = c.roots[0].clone();
    let lock = RwLock::new(Index::build(&c));
    let changed = |paths: &[&str]| paths.iter().map(|p| root.join(p)).collect::<HashSet<PathBuf>>();

    tree(t.path(), &["a/two.txt", "newdir/sub/three.txt", "proj/node_modules/m.js", "a/Bar.app/Contents/x"]);
    apply(&lock, changed(&["a/two.txt", "newdir", "proj/node_modules/m.js", "a/Bar.app/Contents/x"]));
    let idx = lock.read().unwrap();
    assert_eq!(names(&idx, "two"), vec!["two.txt"]);
    assert_eq!(rel(&idx, "three"), vec!["newdir/sub/three.txt"]);
    assert!(names(&idx, "m.js").is_empty());
    assert_eq!(names(&idx, "bar"), vec!["Bar.app"]);
    drop(idx);

    fs::remove_file(t.path().join("a/one.txt")).unwrap();
    fs::rename(t.path().join("newdir"), t.path().join("moved")).unwrap();
    apply(&lock, changed(&["a/one.txt", "newdir", "moved"]));
    let idx = lock.read().unwrap();
    assert!(names(&idx, "one").is_empty());
    assert_eq!(rel(&idx, "three"), vec!["moved/sub/three.txt"]);
    assert_eq!(rel(&idx, "sub")[0], "moved/sub");
    // root, a, a/two.txt, a/Bar.app, proj, proj/src, proj/src/x.js, moved, moved/sub, moved/sub/three.txt
    assert_eq!(idx.len(), 10);
}

#[test]
fn resync_drops_children_missing_from_listing() {
    let t = tempfile::tempdir().unwrap();
    tree(t.path(), &["d/f.txt", "d/g.txt", "Foo/inner.txt"]);
    let c = cfg(t.path());
    let root = c.roots[0].clone();
    let lock = RwLock::new(Index::build(&c));
    let changed = |paths: &[&str]| paths.iter().map(|p| root.join(p)).collect::<HashSet<PathBuf>>();

    // Only the directory is reported after a delete inside it.
    fs::remove_file(t.path().join("d/f.txt")).unwrap();
    apply(&lock, changed(&["d"]));
    assert!(!rel(&lock.read().unwrap(), "f.txt").contains(&"d/f.txt".to_string()));
    assert_eq!(names(&lock.read().unwrap(), "g.txt"), vec!["g.txt"]);

    // Case-only rename: the old name still stats fine on APFS, so the listing must decide.
    fs::rename(t.path().join("Foo"), t.path().join("foo")).unwrap();
    apply(&lock, changed(&["Foo", "foo"]));
    let idx = lock.read().unwrap();
    assert_eq!(rel(&idx, "foo"), vec!["foo", "foo/inner.txt"]); // no Foo/… left
    assert_eq!(rel(&idx, "inner"), vec!["foo/inner.txt"]);
    assert_eq!(idx.len(), 5); // root, d, d/g.txt, foo, foo/inner.txt
}

#[test]
fn unicode_names_match_either_normalization() {
    let t = tempfile::tempdir().unwrap();
    tree(t.path(), &["cafe\u{301}.txt", "na\u{ef}ve/r\u{e9}sum\u{e9}.pdf"]);
    let idx = Index::build(&cfg(t.path()));
    assert_eq!(names(&idx, "caf\u{e9}"), vec!["cafe\u{301}.txt"]);
    assert_eq!(names(&idx, "cafe\u{301}"), vec!["cafe\u{301}.txt"]);
    assert_eq!(names(&idx, "CAF\u{c9}"), vec!["cafe\u{301}.txt"]);
    assert_eq!(names(&idx, "r\u{e9}sum\u{e9}").len(), 1);
    assert_eq!(names(&idx, "re\u{301}sume\u{301}").len(), 1);
    // Non-ASCII in the folder filter and in a two-character token.
    let hits = idx.search(&Query { query: "r\u{e9}", limit: 50, folder: Some(&t.path().join("na\u{ef}ve")), kind: None, dirs_only: false });
    assert_eq!(hits.len(), 1);
    assert!(hits[0].path.ends_with("re\u{301}sume\u{301}.pdf"));
}
