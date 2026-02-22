import { Controller } from "@hotwired/stimulus";

const SNAKE_COUNT = 16;
const SUBSTEPS = 5;

function wrapAngle(angle) {
  while (angle > Math.PI) angle -= Math.PI * 2;
  while (angle < -Math.PI) angle += Math.PI * 2;
  return angle;
}

function randomBetween(min, max) {
  return min + Math.random() * (max - min);
}

export default class extends Controller {
  connect() {
    this.canvas = this.element;
    this.ctx = this.canvas.getContext("2d", { alpha: true });
    if (!this.ctx) return;

    this.width = 0;
    this.height = 0;
    this.snakes = [];
    this.rafId = null;

    const pageBg = getComputedStyle(document.body).backgroundColor;
    const bgMatch = pageBg.match(/\d+/g);
    this.bgRgb =
      bgMatch && bgMatch.length >= 3
        ? bgMatch.slice(0, 3).join(", ")
        : "254, 254, 254";
    this.fadeStrength = 0.01;
    this.palette = [
      "#ff3b7a",
      "#ff8a00",
      "#ffd700",
      "#00b894",
      "#00a8ff",
      "#6c5ce7",
      "#b337ff",
      "#ff4d4d",
    ];

    this.resize = this.resize.bind(this);
    this.tick = this.tick.bind(this);
    this.handleGlobalClick = this.handleGlobalClick.bind(this);

    this.resize();
    window.addEventListener("resize", this.resize);
    document.addEventListener("click", this.handleGlobalClick);
    this.rafId = window.requestAnimationFrame(this.tick);
  }

  disconnect() {
    window.removeEventListener("resize", this.resize);
    document.removeEventListener("click", this.handleGlobalClick);
    if (this.rafId) window.cancelAnimationFrame(this.rafId);
    this.rafId = null;
  }

  makeSnake(
    i,
    x = randomBetween(0, this.width),
    y = randomBetween(0, this.height),
  ) {
    return {
      x,
      y,
      px: x,
      py: y,
      heading: randomBetween(0, Math.PI * 2),
      turnBias: randomBetween(-0.03, 0.03),
      phase: randomBetween(0, Math.PI * 2),
      baseSpeed: randomBetween(0.8, 1.7),
      color: this.palette[i % this.palette.length],
      orbit: {
        active: false,
        cx: 0,
        cy: 0,
        radius: 0,
        ttl: 0,
        dir: Math.random() > 0.5 ? 1 : -1,
      },
    };
  }

  handleGlobalClick(event) {
    const rect = this.canvas.getBoundingClientRect();
    const x = event.clientX - rect.left;
    const y = event.clientY - rect.top;
    if (x < 0 || y < 0 || x > rect.width || y > rect.height) return;
    this.snakes.push(this.makeSnake(this.snakes.length, x, y));
  }

  resize() {
    const dpr = Math.max(1, window.devicePixelRatio || 1);
    this.width = Math.floor(window.innerWidth);
    this.height = Math.floor(window.innerHeight);
    this.canvas.width = Math.floor(this.width * dpr);
    this.canvas.height = Math.floor(this.height * dpr);
    this.canvas.style.width = `${this.width}px`;
    this.canvas.style.height = `${this.height}px`;

    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.ctx.imageSmoothingEnabled = true;
    this.ctx.fillStyle = `rgba(${this.bgRgb}, 1)`;
    this.ctx.fillRect(0, 0, this.width, this.height);

    this.snakes = Array.from({ length: SNAKE_COUNT }, (_, i) =>
      this.makeSnake(i),
    );
  }

  maybeStartOrbit(snake, stepScale) {
    if (snake.orbit.active || Math.random() > 0.015 * stepScale) return;
    snake.orbit.active = true;
    snake.orbit.radius = randomBetween(55, 180);
    snake.orbit.cx =
      snake.x + Math.cos(snake.heading + Math.PI / 2) * snake.orbit.radius;
    snake.orbit.cy =
      snake.y + Math.sin(snake.heading + Math.PI / 2) * snake.orbit.radius;
    snake.orbit.ttl = randomBetween(45, 140);
    snake.orbit.dir = Math.random() > 0.5 ? 1 : -1;
  }

  updateSnake(snake, t, stepScale) {
    const prevX = snake.x;
    const prevY = snake.y;

    this.maybeStartOrbit(snake, stepScale);

    let turn = Math.sin(t * 0.0016 + snake.phase) * 0.07 + snake.turnBias;

    if (snake.orbit.active) {
      const tx =
        snake.orbit.cx +
        Math.cos(t * 0.003 * snake.orbit.dir + snake.phase) *
          snake.orbit.radius;
      const ty =
        snake.orbit.cy +
        Math.sin(t * 0.003 * snake.orbit.dir + snake.phase) *
          snake.orbit.radius;
      const desired = Math.atan2(ty - snake.y, tx - snake.x);
      turn += wrapAngle(desired - snake.heading) * 0.22;
      snake.orbit.ttl -= stepScale;
      if (snake.orbit.ttl <= 0) snake.orbit.active = false;
    }

    const edgePad = 70;
    if (snake.x < edgePad) turn += 0.05;
    if (snake.x > this.width - edgePad) turn -= 0.05;
    if (snake.y < edgePad) turn += 0.05;
    if (snake.y > this.height - edgePad) turn -= 0.05;

    snake.heading += turn;

    const speedBoost = Math.min(1.8, Math.abs(turn) * 24);
    const speed = (snake.baseSpeed + speedBoost) * stepScale;

    let nextX = snake.x + Math.cos(snake.heading) * speed;
    let nextY = snake.y + Math.sin(snake.heading) * speed;
    let wrapped = false;

    if (nextX < -20) {
      nextX = this.width + 20;
      wrapped = true;
    } else if (nextX > this.width + 20) {
      nextX = -20;
      wrapped = true;
    }

    if (nextY < -20) {
      nextY = this.height + 20;
      wrapped = true;
    } else if (nextY > this.height + 20) {
      nextY = -20;
      wrapped = true;
    }

    snake.x = nextX;
    snake.y = nextY;

    if (wrapped) {
      snake.px = snake.x;
      snake.py = snake.y;
      return;
    }

    snake.px = prevX;
    snake.py = prevY;

    const mx = (snake.px + snake.x) * 0.5;
    const my = (snake.py + snake.y) * 0.5;
    const bend = Math.max(-28, Math.min(28, turn * 320));
    const cpx = mx + Math.cos(snake.heading + Math.PI / 2) * bend;
    const cpy = my + Math.sin(snake.heading + Math.PI / 2) * bend;

    this.ctx.beginPath();
    this.ctx.moveTo(snake.px, snake.py);
    this.ctx.quadraticCurveTo(cpx, cpy, snake.x, snake.y);
    this.ctx.lineCap = "round";
    this.ctx.lineJoin = "round";
    this.ctx.lineWidth = 3.6;
    this.ctx.strokeStyle = snake.color;
    this.ctx.globalAlpha = 0.9;
    this.ctx.stroke();
    this.ctx.globalAlpha = 1;
  }

  tick(t) {
    this.ctx.save();
    this.ctx.globalCompositeOperation = "destination-out";
    this.ctx.fillStyle = `rgba(0, 0, 0, ${this.fadeStrength})`;
    this.ctx.fillRect(0, 0, this.width, this.height);
    this.ctx.restore();

    for (let step = 0; step < SUBSTEPS; step += 1) {
      const stepTime = t + step * 2;
      const stepScale = 1 / SUBSTEPS;
      this.snakes.forEach((snake) =>
        this.updateSnake(snake, stepTime, stepScale),
      );
    }
    this.rafId = window.requestAnimationFrame(this.tick);
  }
}
