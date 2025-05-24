import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:typed_data';

String fingerprint() {
// Assuming you have the certificate as a PEM string
  String certificatePem = '''-----BEGIN CERTIFICATE-----
MIIDETCCAfkCFEtWAs2R7xuwFvkze6b7C0mNodXKMA0GCSqGSIb3DQEBCwUAMEUx
CzAJBgNVBAYTAkFVMRMwEQYDVQQIDApTb21lLVN0YXRlMSEwHwYDVQQKDBhJbnRl
cm5ldCBXaWRnaXRzIFB0eSBMdGQwHhcNMjAwNTE3MDQxMTIwWhcNMzAwNTE1MDQx
MTIwWjBFMQswCQYDVQQGEwJBVTETMBEGA1UECAwKU29tZS1TdGF0ZTEhMB8GA1UE
CgwYSW50ZXJuZXQgV2lkZ2l0cyBQdHkgTHRkMIIBIjANBgkqhkiG9w0BAQEFAAOC
AQ8AMIIBCgKCAQEArFIXTH4jpYsXOTfxqCU2N6O7HineJk/UXR0N5Thf15fJC29x
Uhs7VhnJJWNDGoTCn+bPa4DYe5DDp96XH8t+yj4zgc4HptSne3FNHBYytFvYPP3L
aqlBKsuBoW6vCUmGYCEAAYxakAySxCfwS6q8w/a/L9qdSN0YaIldvhqRpceWRX1L
EqCt3eX+p2DZq8u9Gg9out9pAU4g5WkmXDhJGv7okekZ2lvmgmk7pYqG+qtDCg9q
+v/Y5bBsh3MMwwZv4BQ+4+iWcqBEzLrWe+gq4Zw6cVs06ytnWxoBTTxE2VeXJZt2
5l2to4Ql+eulD7M2KACPcR4XoefhIjl1/w4kqQIDAQABMA0GCSqGSIb3DQEBCwUA
A4IBAQBK3tyv1r3mMBxgHb3chNDtoqcdMQH4eznLQwKKvD/N6FLpDIoRL8BBShFa
v5P+MWpsAzn9PpMxDLIJlzmJKcgxh/dA+CC8rj5Zdiyepzs8V5jMz9lL5htJeN/b
nGn2BjuUqyzwlIKmiQADnhYxcD7gOJzfnXGrYPxnQoRujocnSrrgPyYfS08bDaP8
lnEvp3yUlo4uRDqs24V+SdDfOSBGaSAlMjtugHc/GAN2jE1IOLbWGv2XJm0FL5IT
B8GwHtA40Ar2XRQJdJhGkoMARqcOPbXKLy3EOUEMHbNAvwu+smqqn22zC0btKP39
AtQOdUkFbpbYBfEjOzp2AtgUk1W+
-----END CERTIFICATE-----''';

// Convert PEM to DER (remove the header and footer)
  String cleanPem = certificatePem
      .replaceAll(RegExp(r'-----BEGIN CERTIFICATE-----'), '')
      .replaceAll(RegExp(r'-----END CERTIFICATE-----'), '')
      .replaceAll(RegExp(r'\s+'), ''); // Remove any whitespace
  List<int> certBytes = base64Decode(cleanPem);

// Create SHA-256 fingerprint
  Digest fingerprint = sha256.convert(certBytes);

// Convert to uppercase hexadecimal representation
  String fingerprintHex = fingerprint.toString().toUpperCase();
  print("Fingerprint: $fingerprintHex");
  // Format the digest as a colon-separated string
  String fingerprintOut = fingerprintHex;
  fingerprintOut = fingerprintOut
      .replaceAllMapped(RegExp(r'.{2}'), (match) => '${match.group(0)}:')
      .substring(
          0, (fingerprintOut.length + fingerprintOut.length ~/ 2).toInt());

  fingerprintOut = fingerprintOut.substring(0, fingerprintOut.length - 1);
  return fingerprintOut;
}
