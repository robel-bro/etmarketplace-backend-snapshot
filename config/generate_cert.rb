require 'openssl'

key = OpenSSL::PKey::RSA.new(2048)
cert = OpenSSL::X509::Certificate.new
cert.version = 2
cert.serial = 1
cert.subject = OpenSSL::X509::Name.parse("/CN=localhost")
cert.issuer = cert.subject
cert.public_key = key.public_key
cert.not_before = Time.now
cert.not_after = Time.now + 365 * 24 * 60 * 60

ef = OpenSSL::X509::ExtensionFactory.new
ef.subject_certificate = cert
ef.issuer_certificate = cert
cert.add_extension(ef.create_extension("basicConstraints","CA:TRUE",true))
cert.add_extension(ef.create_extension("subjectKeyIdentifier","hash"))
cert.sign(key, OpenSSL::Digest.new('SHA256'))

File.write("config/localhost.key", key.to_pem)
File.write("config/localhost.crt", cert.to_pem)
puts "Certificate generated!"