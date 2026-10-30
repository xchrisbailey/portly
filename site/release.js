// Keep the release-page fallback usable without JavaScript or when GitHub rate-limits requests.
async function updateDownload() {
  try {
    const response = await fetch("https://api.github.com/repos/xchrisbailey/portly/releases/latest");
    if (!response.ok) return;
    const release = await response.json();
    const asset = release.assets?.find((asset) => /^Portly-.*\.dmg$/.test(asset.name));
    if (!asset) return;
    const url = new URL(asset.browser_download_url);
    if (url.origin !== "https://github.com" || !url.pathname.startsWith("/xchrisbailey/portly/releases/download/")) return;
    document.getElementById("download").href = url.href;
    document.getElementById("release-version").textContent = ` · ${release.tag_name}`;
  } catch {
    // Offline visitors can still follow the original release link.
  }
}

updateDownload();
