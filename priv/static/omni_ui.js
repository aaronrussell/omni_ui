// OmniUI client-side event handlers.
// Import this file in your app.js to enable clipboard and other UI features.

window.addEventListener("phx:omni-ui:clipboard", (event) => {
  if (event.detail.text != null) {
    navigator.clipboard.writeText(event.detail.text);
  }
})

document.addEventListener("omni-ui:copied", (event) => {
  const el = event.target;
  setTimeout(() => el.classList.remove("success"), 2000);
})
