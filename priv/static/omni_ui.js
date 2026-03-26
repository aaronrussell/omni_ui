// OmniUI client-side event handlers.
// Import this file in your app.js to enable clipboard and other UI features.

// Clipboard: copies text to the system clipboard via a LiveView push event.
// Second event clears a temporary success state on the triggering element.
(() => {
  window.addEventListener("phx:omni-ui:clipboard", (event) => {
    if (event.detail.text != null) {
      navigator.clipboard.writeText(event.detail.text);
    }
  });

  document.addEventListener("omni-ui:copied", (event) => {
    const el = event.target;
    setTimeout(() => el.classList.remove("success"), 2000);
  });
})();

// Scroll lock: prevents jarring scroll jumps when navigating to a shorter
// branch by locking the content area's min-height via a CSS variable, then
// using an IntersectionObserver on a sentinel element to release it once the
// user scrolls up past the phantom space.
(() => {
  let observer = null;

  document.addEventListener("omni-ui:scroll-lock", (event) => {
    const el = event.target;
    document.body.style.setProperty("--scroll-lock", (el.scrollTop + el.clientHeight) + "px");

    if (observer) {
      observer.disconnect();
      observer = null;
    }
  });

  window.addEventListener("phx:omni-ui:observe-scroll-lock", () => {
    const root = document.querySelector("#scroll-lock");
    const sentinel = document.querySelector("#sentinel");

    observer = new IntersectionObserver((entries) => {
      if (!entries[0].isIntersecting) {
        document.body.style.removeProperty("--scroll-lock");
        observer.disconnect();
        observer = null;
      }
    }, { root, rootMargin: "0px 0px -50px 0px" });

    observer.observe(sentinel);
  });
})();
