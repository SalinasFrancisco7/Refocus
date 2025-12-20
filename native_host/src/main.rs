mod protocol;

use std::env;
use std::io::{self, Write};
use std::os::unix::net::UnixStream;

fn socket_path() -> String {
    env::var("REFOCUS_SOCKET").unwrap_or_else(|_| "/tmp/refocus.sock".to_string())
}

fn forward_message(message: &[u8]) -> io::Result<()> {
    let mut stream = match UnixStream::connect(socket_path()) {
        Ok(stream) => stream,
        Err(_) => {
            return Ok(());
        }
    };

    stream.write_all(message)?;
    stream.write_all(b"\n")?;
    Ok(())
}

fn main() -> io::Result<()> {
    let stdin = io::stdin();
    let mut handle = stdin.lock();

    while let Some(message) = protocol::read_native_message(&mut handle)? {
        forward_message(&message)?;
    }

    Ok(())
}
