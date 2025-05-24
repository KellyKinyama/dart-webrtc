// import {SdpEncryptionKey} from "../../../inerfaces/Sdp";

import '../interface.dart';

SdpEncryptionKey kLineParser(String line) {
  final lineContent = line.replaceFirst('k=', '');
  final [method,encryptionKey] = lineContent.split(':');
  const allowedMethod = ['clear','base64','uri','prompt'];
  if(!allowedMethod.includes(method)){
    throw new Error(`Encryption method "${method}" is not supported by RFC-4566`)
  }
  return {
    method: method as 'clear' | 'base64' | 'uri' | 'prompt',
    encryptionKey
  }
}