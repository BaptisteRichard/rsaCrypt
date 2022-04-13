# rsaCrypt : Crypt a filewith a public RSA key

rsaCrypt allows you to crypt a file before sending it via an unsecure channel. RSA public key can be either manually provided or automatically downloaded from gitlab user's keys (only the first RSA key will be used)

This project is loosely based on [Catacomb](https://github.com/twe4ked/catacomb) for the key retrieval and general structure but does a bit more.

# Prerequisites

`openssl`, `shred` and `ssh-keygen` are needed.

# Usage 

## Decrypt a file 

If it's your default RSA pubkey (`~/.ssh/id_rsa.pub`) that was used for encryption :

`./rsaCrypt.sh file.enc > file`

If it's another RSA key, you will need to specify the correct private key 

`./rsaCrypt.sh -i ~/.ssh/mykey_rsa file.enc > file`

## Encrypt a file

### Via a _gitlab_ login

To **encrypt** (-e) a file for **gitlab** (-g) user _alice_

`./rsaCrypt.sh -e -g alice file > file.enc`

### Via a stored public key

`./rsaCrypt.sh -e -i ~/.ssh/alice.pub file > file.enc`

# How it works

RSA allows for encryption of short messages with public key, but only up to the key modulus size. So it mostly can't be used to encrypt a file.

rsaCrypt first creates a random secret key (_secret_) `aes256`, then encrypt the file with this _secret_. Then it encrypts the _secret_ with the provided RSA public key, smash it all together in a single string with a separator and BAM, you're done.

Decryption consists in separating the message from the _secret_, decrypting the _secret_ with your private RSA key, and then decrypting the message with the _secret_

## Word for the wise

`ssh-keygen` stores RSA private keys using it's own format by default (file beginning with `--- BEGIN OPENSSH PRIVATE KEY ---`) which can't be used by `openssl rsautl`.

That will not prevent your from encrypting, as public keys are standard, but it's a pein in the ass for the decryption process.

rsaCrypt handles that by copying your private key in a temp directory, re-encoding it to PEM (and dropping the passphrase protection), decrypting all that's needed and shredding + deleting the copied private key.

That's why you might see the following in STDERR 
```
ecryption failed , reencoding key
Your identification has been saved with the new passphrase.
```

Don't worry, the unprotected key is securely shredded and removed afterwards, even in the case of SIGINT (however, not in case of SIGKILL or any other hard-wired temination, such as a sledgehammer)
