use serde_json::Value;
use std::io::{BufRead, BufReader, Write};
use std::process::{Command, Stdio};

#[test]
fn round_trip() {
    let t = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(t.path().join("Downloads")).unwrap();
    std::fs::write(t.path().join("Downloads/contract.pdf"), "x").unwrap();
    std::fs::write(t.path().join("junk.tmp"), "x").unwrap();

    let mut child = Command::new(env!("CARGO_BIN_EXE_macotron-index"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut stdin = child.stdin.take().unwrap();
    let mut stdout = BufReader::new(child.stdout.take().unwrap());
    let mut ask = |req: String| -> Value {
        writeln!(stdin, "{req}").unwrap();
        let mut line = String::new();
        stdout.read_line(&mut line).unwrap();
        serde_json::from_str(&line).unwrap()
    };

    let root = t.path().to_string_lossy().into_owned();
    let r = ask(format!(r#"{{"id":1,"op":"configure","roots":[{root:?}],"ignore":["*.tmp"],"hidden":false,"ignoreFiles":true}}"#));
    assert_eq!(r["id"], 1);
    assert_eq!(r["ok"], true);

    let mut results = Vec::new();
    for _ in 0..200 {
        let r = ask(r#"{"id":2,"op":"search","query":"con","limit":50,"kind":"pdf"}"#.into());
        assert_eq!(r["ok"], true);
        if r["indexing"] == false {
            results = r["results"].as_array().unwrap().clone();
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    assert_eq!(results.len(), 1);
    assert_eq!(results[0]["name"], "contract.pdf");
    assert_eq!(results[0]["score"], 900);
    assert_eq!(results[0]["isDir"], false);
    assert!(results[0]["modified"].as_u64().unwrap() > 0);
    assert!(results[0]["path"].as_str().unwrap().ends_with("/Downloads/contract.pdf"));

    let r = ask(r#"{"id":3,"op":"search","query":"junk"}"#.into());
    assert_eq!(r["results"].as_array().unwrap().len(), 0);

    let r = ask(r#"{"id":4,"op":"status"}"#.into());
    assert_eq!(r["entries"], 3);
    assert_eq!(r["watching"], true);
    assert!(r["memoryBytes"].as_u64().unwrap() > 0);
    assert!(r["lastIndexed"].as_u64().unwrap() > 0);

    let r = ask(r#"{"id":5,"op":"bogus"}"#.into());
    assert_eq!(r["ok"], false);
    let r = ask("not json".into());
    assert_eq!(r["ok"], false);
    let r = ask(r#"{"id":7,"op":"search","query":"x","limit":-1}"#.into());
    assert_eq!(r["ok"], true);
    let r = ask(r#"{"id":8,"op":"configure","roots":[1]}"#.into());
    assert_eq!(r["ok"], false);
    assert_eq!(r["id"], 8);


    let r = ask(r#"{"id":6,"op":"shutdown"}"#.into());
    assert_eq!(r["ok"], true);
    assert!(child.wait().unwrap().success());
}

#[test]
fn exits_on_eof() {
    let mut child = Command::new(env!("CARGO_BIN_EXE_macotron-index")).stdin(Stdio::piped()).stdout(Stdio::piped()).spawn().unwrap();
    drop(child.stdin.take());
    assert!(child.wait().unwrap().success());
}

#[test]
fn invalid_utf8_line_is_a_bad_request_not_an_exit() {
    let mut child = Command::new(env!("CARGO_BIN_EXE_macotron-index")).stdin(Stdio::piped()).stdout(Stdio::piped()).spawn().unwrap();
    let mut stdin = child.stdin.take().unwrap();
    let mut stdout = BufReader::new(child.stdout.take().unwrap());
    stdin.write_all(&[b'{', 0xff, b'}', b'\n']).unwrap();
    stdin.write_all(b"{\"id\":1,\"op\":\"status\"}\n").unwrap();
    let mut line = String::new();
    stdout.read_line(&mut line).unwrap();
    let r: Value = serde_json::from_str(&line).unwrap();
    assert_eq!(r["ok"], false);
    line.clear();
    stdout.read_line(&mut line).unwrap();
    let r: Value = serde_json::from_str(&line).unwrap();
    assert_eq!(r["id"], 1);
    assert_eq!(r["ok"], true);
    drop(stdin);
    assert!(child.wait().unwrap().success());
}
