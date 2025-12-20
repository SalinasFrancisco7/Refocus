use std::io::{self, Read};

pub fn read_native_message<R: Read>(reader: &mut R) -> io::Result<Option<Vec<u8>>> {
    let mut length_bytes = [0u8; 4];
    let read_len = reader.read(&mut length_bytes)?;
    if read_len == 0 {
        return Ok(None);
    }
    if read_len < 4 {
        return Err(io::Error::new(
            io::ErrorKind::UnexpectedEof,
            "native message length truncated",
        ));
    }

    let message_length = u32::from_le_bytes(length_bytes) as usize;
    let mut message = vec![0u8; message_length];
    reader.read_exact(&mut message)?;
    Ok(Some(message))
}
