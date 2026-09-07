(function () {
  "use strict";

  const REPO = "mertizci/browser-picker";

  /* Copy-to-clipboard for the Homebrew commands. */
  document.querySelectorAll(".copy-btn").forEach(function (button) {
    button.addEventListener("click", async function () {
      const source = document.querySelector(button.dataset.copy);
      if (!source) return;

      try {
        await navigator.clipboard.writeText(source.textContent.trim());
      } catch {
        return; // Clipboard unavailable (insecure context, denied permission).
      }

      button.classList.add("copied");
      button.setAttribute("aria-label", "Copied");
      setTimeout(function () {
        button.classList.remove("copied");
        button.setAttribute("aria-label", "Copy Homebrew command");
      }, 1600);
    });
  });

  /* Point the download buttons straight at the latest DMG and show its version.
     Falls back silently to the releases page already in the markup. */
  fetch("https://api.github.com/repos/" + REPO + "/releases/latest", {
    headers: { Accept: "application/vnd.github+json" },
  })
    .then(function (response) {
      if (!response.ok) throw new Error("Release lookup failed");
      return response.json();
    })
    .then(function (release) {
      const dmg = (release.assets || []).find(function (asset) {
        return asset.name.toLowerCase().endsWith(".dmg");
      });

      if (dmg) {
        ["#download-btn", "#dmg-btn"].forEach(function (selector) {
          const link = document.querySelector(selector);
          if (link) link.href = dmg.browser_download_url;
        });
      }

      const tag = release.tag_name;
      if (!tag) return;

      const versionLine = document.getElementById("version-line");
      if (versionLine) versionLine.textContent = "Version " + tag.replace(/^v/, "");

      const note = document.getElementById("release-note");
      if (note) note.textContent = tag + " · Universal build · macOS 14.0 or later";
    })
    .catch(function () {
      /* Keep the static links — nothing to do. */
    });
})();
