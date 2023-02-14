use tokio::io::{AsyncReadExt, self, AsyncWriteExt};
use thiserror::Error;
use paste::paste;

#[derive(Error, Debug)]
pub enum LapasProtocolError {
    #[error("IO Error")]
    IOError(#[from] io::Error),
    #[error("ProtocolError: {0}")]
    ProtocolError(String)
}



#[async_trait::async_trait]
pub trait ProtoSerde : Sized + Sync {
    async fn decode<R: AsyncReadExt + Send + Unpin>(reader: &mut R) -> Result<Self, LapasProtocolError>;
    async fn encode<W: AsyncWriteExt + Send + Unpin>(&self, writer: &mut W) -> Result<(), LapasProtocolError>;
}

macro_rules! impl_protoserde_for_basic_datatype {
    ($($datatype:ident),*) => {
        $(
            impl_protoserde_for_basic_datatype!(@single $datatype);
        )*
    };
    (@single $datatype:ident) => {
        #[async_trait::async_trait]
        impl ProtoSerde for $datatype {
            async fn decode<R: AsyncReadExt + Send + Unpin>(reader: &mut R) -> Result<$datatype, LapasProtocolError> {
                paste! {
                    Ok(reader.[<read_ $datatype>]().await?)
                }
            }
            async fn encode<W: AsyncWriteExt + Send + Unpin>(&self, writer: &mut W) -> Result<(), LapasProtocolError> {
                paste! {
                    writer.[<write_ $datatype>](*self).await?;
                }
                Ok(())
            }
        }
    };
}
impl_protoserde_for_basic_datatype!(u8, i8, u16, i16, u32, i32, u64, i64, f32, f64);

#[async_trait::async_trait]
impl ProtoSerde for () {
    async fn decode<R: AsyncReadExt + Send + Unpin>(_: &mut R) -> Result<Self, LapasProtocolError> { Ok(()) }
    async fn encode<W: AsyncWriteExt + Send + Unpin>(&self, _: &mut W) -> Result<(), LapasProtocolError> { Ok(()) }
}

#[async_trait::async_trait]
impl<TOk: ProtoSerde, TErr: ProtoSerde> ProtoSerde for Result<TOk, TErr> {
    async fn decode<R: AsyncReadExt + Send + Unpin>(reader: &mut R) -> Result<Self, LapasProtocolError> {
        let tag = reader.read_u8().await?;
        match tag {
            0 => Ok(Ok( TOk::decode(reader).await? )),
            1 => Ok(Err( TErr::decode(reader).await? )),
            _ => Err(LapasProtocolError::ProtocolError("Error while deserializing Result<,>. Tag".to_owned()))
        }
    }
    async fn encode<W: AsyncWriteExt + Send + Unpin>(&self, writer: &mut W) -> Result<(), LapasProtocolError> {
        match self {
            Ok(ok) => {
                writer.write_u8(0).await?;
                ok.encode(writer).await?;
            },
            Err(err) => {
                writer.write_u8(1).await?;
                err.encode(writer).await?;
            },
        }
        Ok(())
    }
}

#[async_trait::async_trait]
impl<T: ProtoSerde> ProtoSerde for Option<T> {
    async fn decode<R: AsyncReadExt + Send + Unpin>(reader: &mut R) -> Result<Self, LapasProtocolError> {
        let tag = reader.read_u8().await?;
        match tag {
            0 => Ok(None),
            1 => Ok(Some(T::decode(reader).await?)),
            _ => Err(LapasProtocolError::ProtocolError("Error while deserializing Option. Invalid tag".to_owned()))
        }
    }
    async fn encode<W: AsyncWriteExt + Send + Unpin>(&self, writer: &mut W) -> Result<(), LapasProtocolError> {
        match self {
            Some(val) => {
                writer.write_u8(1).await?;
                val.encode(writer).await?;
            },
            None => writer.write_u8(0).await?,
        }
        Ok(())
    }
}

#[async_trait::async_trait]
impl ProtoSerde for String {
    async fn decode<R: AsyncReadExt + Send + Unpin>(reader: &mut R) -> Result<Self, LapasProtocolError> {
        let len = reader.read_u32().await?;
        let mut str_bytes = Vec::<u8>::with_capacity(len as usize);
        unsafe { str_bytes.set_len(str_bytes.capacity()); }
        reader.read_exact(&mut str_bytes).await?;
        Ok(
            String::from_utf8(str_bytes)
                .map_err(|_| LapasProtocolError::ProtocolError("Error while deserializing String. Invalid encoding".to_owned()))?
        )
    }
    async fn encode<W: AsyncWriteExt + Send + Unpin>(&self, writer: &mut W) -> Result<(), LapasProtocolError> {
        writer.write_u32(self.len() as u32).await?;
        writer.write_all(self.as_bytes()).await?;
        Ok(())
    }
}

macro_rules! define_protocol {
    (
        proto $protoname:ident {
            $(
                $packetname:ident {
                    $(
                        $fieldname:ident : $fieldtype:ty
                    ),*
                }
            ),*
        }
    ) => {
        #[derive(Debug, Clone)]
        pub enum $protoname {
            $(
                $packetname {
                    $($fieldname : $fieldtype,)*
                }
            ,)*
        }

        #[async_trait::async_trait]
        impl ProtoSerde for $protoname {
            async fn decode<R: tokio::io::AsyncReadExt + Send + Unpin>(reader: &mut R) -> Result<Self, LapasProtocolError> {
                let tag = reader.read_u32().await?;
                let mut pkt_tag = 0u32..;

                $(
                    if tag == pkt_tag.next().unwrap() {
                        return Ok(
                            $protoname::$packetname {
                                $(
                                    $fieldname: <$fieldtype>::decode(reader).await?,
                                )*
                            }
                        );
                    }
                )*

                Err(LapasProtocolError::ProtocolError("Unknown Packet received".to_owned()))
            }
            async fn encode<W: tokio::io::AsyncWriteExt + Send + Unpin>(&self, writer: &mut W) -> Result<(), LapasProtocolError> {
                let mut pkt_tag = 0u32;
                $(
                    if let $protoname::$packetname { $($fieldname),* } = self {
                        writer.write_u32(pkt_tag).await?;
                        $(
                            $fieldname.encode(writer).await?;
                        )*
                        return Ok(())
                    } else {
                        pkt_tag += 1;
                    }
                )*
                drop(pkt_tag);

                Ok(())
            }
        }
    };
}
pub(crate) use define_protocol;