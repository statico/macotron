//! `cargo run --release --example bench` — indexes $HOME and /Applications
//! with the default ignore list and reports the budget numbers.
use macotron_index::{resident_bytes, Config, Index, Query};
use std::time::Instant;

fn main() {
    let home = std::env::var("HOME").unwrap();
    let cfg = Config {
        roots: vec![home.into(), "/Applications".into()],
        ignore: ["node_modules", "*.tmp", "Library/Caches", "Library/Containers", "Library/Group Containers", "Library/pnpm", "Library/Developer/Xcode/DerivedData", "go/pkg"]
            .iter()
            .map(|s| s.to_string())
            .collect(),
        hidden: false,
        ignore_files: true,
    }
    .normalized();
    let t = Instant::now();
    let idx = Index::build(&cfg);
    println!("build: {:?}, entries: {}, rss: {} MB, arenas+tables: {} MB", t.elapsed(), idx.len(), resident_bytes() >> 20, idx.heap_bytes() >> 20);
    for q in ["con", "ind", "bud", "q3 bud", "docdad"] {
        let t = Instant::now();
        let hits = idx.search(&Query { query: q, limit: 50, folder: None, kind: None, dirs_only: false });
        let dt = t.elapsed();
        let top: Vec<String> = hits.iter().take(3).map(|h| format!("{} ({})", h.name, h.score)).collect();
        println!("search {q:?}: {dt:?}, {} hits, top: {}", hits.len(), top.join(", "));
    }
}
