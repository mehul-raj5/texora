## Install Texora {{VERSION}}

1. Download **Texora-{{VERSION}}.dmg** below and open it.
2. Drag **Texora** into **Applications**.
3. **Run this once in Terminal** (macOS blocks apps that aren't signed by Apple, and Texora isn't yet):

   ```bash
   xattr -cr /Applications/Texora.app
   ```

4. Open Texora from Applications.

If you skip step 3, macOS says the app "is damaged" or "can't be opened". Run the command above, or go to **System Settings → Privacy & Security** and click **Open Anyway**.

### Requirements
- A Mac with Apple Silicon, running macOS 15 or later.
- [Claude Code](https://claude.com/claude-code), installed and signed in. Run `claude` once in Terminal to sign in.
- A TeX engine:
  - TinyTeX: install it from Texora → Settings → LaTeX. It's about 100 MB and needs no admin password.
  - Or Tectonic: `brew install tectonic`.
  - Or MacTeX.

The `.sha256` file lets you verify the download: `shasum -a 256 Texora-{{VERSION}}.dmg`.
