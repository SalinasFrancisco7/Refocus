use std::io::Write;
use std::os::unix::net::UnixListener;
use std::process::{Command, Stdio};
use std::time::Duration;

use tempfile::tempdir;

fn encode_message(message: &[u8]) -> Vec<u8> {
    let mut payload = Vec::with_capacity(4 + message.len());
    payload.extend_from_slice(&(message.len() as u32).to_le_bytes());
    payload.extend_from_slice(message);
    payload
}

#[test]
fn forwards_native_messages_to_socket() {
    let dir = tempdir().expect("temp dir");
    let socket_path = dir.path().join("refocus.sock");
    let listener = UnixListener::bind(&socket_path).expect("bind socket");

    let mut child = Command::new(env!("CARGO_BIN_EXE_refocus_native_host"))
        .env("REFOCUS_SOCKET", &socket_path)
        .stdin(Stdio::piped())
        .spawn()
        .expect("spawn host");

    let message = br#"{"type":"TAB_EVENT","url":"https://news.ycombinator.com"}"#;
    let payload = encode_message(message);
    child
        .stdin
        .as_mut()
        .expect("stdin")
        .write_all(&payload)
        .expect("write stdin");

    listener
        .set_nonblocking(true)
        .expect("nonblocking");

    let start = std::time::Instant::now();
    let mut received = None;
    while start.elapsed() < Duration::from_secs(2) {
        match listener.accept() {
            Ok((mut stream, _)) => {
                let mut buffer = Vec::new();
                std::io::Read::read_to_end(&mut stream, &mut buffer).unwrap();
                received = Some(buffer);
                break;
            }
            Err(err) if err.kind() == std::io::ErrorKind::WouldBlock => {
                std::thread::sleep(Duration::from_millis(10));
            }
            Err(err) => panic!("accept failed: {err}"),
        }
    }

    let received = received.expect("receive data");
    let received_str = String::from_utf8_lossy(&received);
    assert!(received_str.contains("\"type\":\"TAB_EVENT\""));

    let _ = child.kill();
}
