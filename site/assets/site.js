(() => {
  const svg = document.querySelector(".dial");
  if (!svg) return;
  const ns = "http://www.w3.org/2000/svg";
  const day = Number(svg.dataset.day || 73);
  const size = 1000, center = size / 2, outer = 470, inner = 440;
  for (let i = 0; i < 365; i++) {
    const angle = (i / 365) * Math.PI * 2 - Math.PI / 2;
    const long = i % 30 === 0;
    const line = document.createElementNS(ns, "line");
    line.setAttribute("x1", center + Math.cos(angle) * (long ? inner - 14 : inner));
    line.setAttribute("y1", center + Math.sin(angle) * (long ? inner - 14 : inner));
    line.setAttribute("x2", center + Math.cos(angle) * outer);
    line.setAttribute("y2", center + Math.sin(angle) * outer);
    line.dataset.index = i;
    svg.appendChild(line);
  }
  const lines = svg.querySelectorAll("line");
  const light = (count) => lines.forEach((line, index) => {
    line.classList.toggle("lit", index < count);
    line.classList.toggle("today", index === count - 1);
  });
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) { light(day); return; }
  let shown = 0;
  const start = performance.now();
  const step = (now) => {
    shown = Math.min(day, Math.round(((now - start) / 1400) * day));
    light(shown);
    if (shown < day) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
})();
