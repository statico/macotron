// Tour carousel: the track scrolls natively; this only plays the slide in
// view, keeps the tabs in step, and wires the arrows.
(() => {
  const track = document.getElementById("tour-track");
  if (!track) return;
  const slides = [...track.children];
  const tabs = [...document.querySelectorAll(".tour-tabs [data-slide]")];
  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
  let current = 0;

  const left = (n) => slides[n].offsetLeft - track.offsetLeft;
  const go = (i) => {
    const n = (i + slides.length) % slides.length;
    if (still) return track.scrollTo({ left: left(n), behavior: "instant" });
    // A far jump would crawl past every slide in between, so cut to the
    // neighbor and glide only the last step.
    if (Math.abs(n - current) > 1) track.scrollTo({ left: left(n > current ? n - 1 : n + 1), behavior: "instant" });
    track.scrollTo({ left: left(n), behavior: "smooth" });
  };

  const seen = new IntersectionObserver((entries) => {
    for (const e of entries) {
      const video = e.target.querySelector("video");
      if (e.intersectionRatio > 0.6) {
        current = slides.indexOf(e.target);
        tabs.forEach((t, i) => t.setAttribute("aria-selected", String(i === current)));
        // Reduced motion keeps the poster; the controls attribute lets a
        // visitor start the clip themselves.
        if (still) video.controls = true;
        else video.play().catch(() => {});
      } else {
        video.pause();
      }
    }
  }, { root: track, threshold: [0, 0.6] });
  slides.forEach((s) => seen.observe(s));

  tabs.forEach((t) => t.addEventListener("click", () => go(Number(t.dataset.slide))));
  document.querySelector(".tour-prev").addEventListener("click", () => go(current - 1));
  document.querySelector(".tour-next").addEventListener("click", () => go(current + 1));

  // Advance to the next clip when one ends, wrapping after the last.
  slides.forEach((s) => s.querySelector("video").addEventListener("ended", () => go(current + 1)));
})();
