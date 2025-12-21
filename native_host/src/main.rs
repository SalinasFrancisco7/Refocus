mod protocol;

use std::env;
use std::io::{self, BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::time::Duration;

fn socket_path() -> String {
    env::var("REFOCUS_SOCKET").unwrap_or_else(|_| "/tmp/refocus.sock".to_string())
}

fn log(msg: &str) {
    if let Ok(mut f) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open("/tmp/refocus_native_host.log")
    {
        let _ = writeln!(f, "[{}] {}", chrono_lite(), msg);
    }
}

fn chrono_lite() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    format!("{}", secs)
}

fn main() -> io::Result<()> {
    log("Native host started");
    let stdin = io::stdin();
    let mut handle = stdin.lock();

    while let Some(message) = protocol::read_native_message(&mut handle)? {
        log(&format!("Received message: {} bytes", message.len()));
        forward_message(&message)?;
    }

    log("Native host exiting (stdin closed)");
    Ok(())
}

fn forward_message(message: &[u8]) -> io::Result<()> {
    let path = socket_path();
    let mut stream = match UnixStream::connect(&path) {
        Ok(stream) => {
            log(&format!("Connected to socket at {}", path));
            stream
        }
        Err(e) => {
            log(&format!("Failed to connect to socket: {}", e));
            send_error_response(&format!("App not running: {}", e))?;
            return Ok(());
        }
    };

    // Set read timeout so we don't hang forever
    stream.set_read_timeout(Some(Duration::from_secs(5)))?;

    // Send message to app
    stream.write_all(message)?;
    stream.write_all(b"\n")?;
    log("Message forwarded to socket");

    // Wait for response from app (newline-delimited)
    let mut reader = BufReader::new(&stream);
    let mut response = String::new();
    match reader.read_line(&mut response) {
        Ok(0) => {
            // Connection closed without response
            log("Socket closed without response");
            send_error_response("App closed connection")?;
        }
        Ok(_) => {
            // Got response from app - forward to Chrome
            let response = response.trim_end();
            log(&format!("Received response: {} bytes", response.len()));
            send_native_response(response.as_bytes())?;
        }
        Err(e) => {
            // Timeout or read error
            log(&format!("Failed to read response: {}", e));
            send_error_response(&format!("Read timeout: {}", e))?;
        }
    }

    Ok(())
}

fn send_error_response(error: &str) -> io::Result<()> {
    let response = format!(r#"{{"error":"{}"}}"#, error);
    let mut stdout = io::stdout().lock();
    let len = response.len() as u32;
    stdout.write_all(&len.to_le_bytes())?;
    stdout.write_all(response.as_bytes())?;
    stdout.flush()?;
    log(&format!("Sent error response: {}", error));
    Ok(())
}

fn send_native_response(message: &[u8]) -> io::Result<()> {
    let mut stdout = io::stdout().lock();
    let len = message.len() as u32;
    stdout.write_all(&len.to_le_bytes())?;
    stdout.write_all(message)?;
    stdout.flush()?;
    log(&format!("Sent native response: {} bytes", message.len()));
    Ok(())
}
