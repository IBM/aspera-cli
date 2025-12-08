# Gem Signature

## References

Refer to:

- <https://guides.rubygems.org/security/>
- <https://ruby-doc.org/current/stdlibs/rubygems/Gem/Security.html>
- `gem cert --help`

## Certificate maintenance

The maintainer creates the initial certificate and a private key:

```bash
cd /path/to/vault
gem cert --build maintainer@example.com
```

> [!NOTE]
> The email must match the field `spec.email` in `aspera-cli.gemspec`

This creates two files in folder `/path/to/vault` (e.g. `$HOME/.ssh`):

- `gem-private_key.pem` : This file shall be kept secret in a vault.
- `gem-public_cert.pem` : This file is copied to a public place, here in folder `certs`

> [!NOTE]
> Alternatively, use an existing key or generate one, and then `make new`

Subsequently, the private key path is specified using `SIGNING_KEY` as env var or `make` macro.

Show the current certificate contents

```bash
make show
```

> [!NOTE]
> To provide a passphrase add argument: `-passin pass:_value_` to `openssl`

Check that the signing key is the same as used to sign the certificate:

```bash
make check-key SIGNING_KEY=/path/to/vault/gem-private_key.pem
```

## Renew certificate after expiration

The maintainer can renew the certificate when it is expired using the same private key:

```bash
make update SIGNING_KEY=/path/to/vault/gem-private_key.pem
```

Alternatively, to generate a new certificate with the same key:

```bash
make new SIGNING_KEY=/path/to/vault/gem-private_key.pem
```

## Build Procedure

See [Contributing](../CONTRIBUTING.md#build)

## Secure installation of gem

Refer to [Manual](../README.md#gem-installation-with-signature-verification)
