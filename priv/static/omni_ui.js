// OmniUI client-side event handlers.
// Import this file in your app.js to enable clipboard and other UI features.

class OmniUI {
  constructor() {
    this.$view = document.querySelector("#omni-view");
    this.$content = document.querySelector("#omni-content");
    this.$sentinel = document.querySelector("#omni-sentinel");

    if (!this.$view) return;

    this.autoScroll = false;
    this.scrollLock = false;
    this.prevScrollTop = this.$view.scrollTop;

    this.#initClipboard();
    this.#initAutoScroll();
    this.#initScrollLock();
  }

  #initClipboard() {
    window.addEventListener("phx:omni:clipboard", (e) => {
      if (e.detail.text != null) {
        navigator.clipboard.writeText(e.detail.text);
      }
    });
  }

  #initAutoScroll() {
    this.$view.addEventListener("scroll", () => {
      const { scrollTop, scrollHeight, clientHeight } = this.$view;
      const distanceFromBottom = scrollHeight - scrollTop - clientHeight;

      if (scrollTop !== 0 && scrollTop < this.prevScrollTop && distanceFromBottom > 64) {
        this.autoScroll = false;
      } else if (distanceFromBottom < 16) {
        this.autoScroll = true;
      }

      this.prevScrollTop = scrollTop;
    });

    const observer = new ResizeObserver(() => {
      if (this.autoScroll) {
        this.$view.scrollTop = this.$view.scrollHeight;
      }
    });

    if (this.$content) observer.observe(this.$content);
  }

  #initScrollLock() {
    const observer = new IntersectionObserver(
      (entries) => {
        if (this.scrollLock && !entries[0].isIntersecting) {
          document.body.style.removeProperty("--scroll-lock");
          this.scrollLock = false;
        }
      },
      { root: this.$view, rootMargin: "0px 0px -64px 0px" }
    );

    document.addEventListener("omni:before-update", () => {
      const lockHeight = this.$view.scrollTop + this.$view.clientHeight;
      document.body.style.setProperty("--scroll-lock", lockHeight + "px");
      this.autoScroll = false;
    });

    window.addEventListener("phx:omni:updated", () => {
      this.scrollLock = true;
    });

    if (this.$sentinel) observer.observe(this.$sentinel);
  }
}

window.addEventListener("phx:page-loading-stop", () => new OmniUI());
