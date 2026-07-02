# Android upload keystore (local only — never commit)

This directory holds the **Play upload keystore** and `key.properties` on developer/CI machines. Both are gitignored.

## Setup

1. Generate a keystore (or restore from your password manager after a rotation):

   ```bash
   keytool -genkey -v -keystore fotozen-upload.jks \
     -keyalg RSA -keysize 2048 -validity 10000 \
     -alias fotozen-upload
   ```

2. Copy `../key.properties.example` to `key.properties` in this folder and fill in passwords.

3. Keep `.jks` + passwords in 1Password / encrypted backup — losing the upload key requires a Google Play upload-key reset.

See `RELEASE_CHECKLIST.md` §2 for release signing details.
