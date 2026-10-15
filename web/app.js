// tb_devtool panel.
//
// Holds no state of its own. Every click posts to Lua, Lua changes the point
// list and pushes the whole thing back, and render() redraws from that. What
// you are looking at is therefore always what the builder actually has, not
// what the last click hoped for.

const panel = document.getElementById('panel');
const list = document.getElementById('points');
const empty = document.getElementById('empty');
const snippet = document.getElementById('snippet');
const count = document.getElementById('count');
const thickness = document.getElementById('thickness');
const thicknessField = document.getElementById('thickness-field');
const nameInput = document.getElementById('name');
const nameField = document.getElementById('name-field');
const fields = document.getElementById('fields');
const zValue = document.getElementById('z-value');

const controls = document.getElementById('controls');
const controlsTitle = document.getElementById('controls-title');
const controlsList = document.getElementById('controls-list');

const statusCard = document.getElementById('status');
const statusFormat = document.getElementById('status-format');
const statusDistance = document.getElementById('status-distance');
const statusTarget = document.getElementById('status-target');
const statusSnap = document.getElementById('status-snap');

const Z_STEP = 0.05;

function post(action, body) {
  return fetch(`https://${GetParentResourceName()}/${action}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(body || {}),
  }).catch(() => {});
}

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function row(point, index, total, isZone, showHeading, offset) {
  const li = el('li');
  li.append(el('span', 'n', index));
  li.append(el('span', 'xy', `${point.x.toFixed(2)}, ${point.y.toFixed(2)}`));

  // The EXPORT height, not the captured one. The Z offset is applied on the
  // way out, so showing the raw value here would disagree with the snippet
  // directly underneath it.
  const z = el('span', isZone ? 'z' : 'z bright', (point.z + offset).toFixed(2));
  li.append(z);

  // Only vector4 exports a heading. Showing it in vec3 mode would advertise a
  // column that never reaches the snippet.
  if (showHeading && point.heading !== undefined) {
    li.append(el('span', 'h', `${point.heading.toFixed(0)}°`));
  }

  const move = (delta, label, enabled) => {
    const button = el('button', null, label);
    button.type = 'button';
    button.disabled = !enabled;
    button.style.visibility = enabled ? 'visible' : 'hidden';
    button.addEventListener('click', () => post('zone:move', { index, delta }));
    return button;
  };

  li.append(move(-1, '↑', index > 1), move(1, '↓', index < total));

  const del = el('button', 'del', '✕');
  del.type = 'button';
  del.addEventListener('click', () => post('zone:remove', { index }));
  li.append(del);

  return li;
}

function render(data) {
  const isZone = !!data.isZone;
  const offset = data.zOffset || 0;

  document.querySelectorAll('.formats button').forEach((button) => {
    button.classList.toggle('on', button.dataset.format === data.format);
  });

  // Thickness and name only mean something to a zone. PolyZone:Create takes a
  // name; lib.zones.poly has nowhere to put one.
  thicknessField.hidden = !isZone;
  nameField.hidden = data.format !== 'polyzone';
  fields.hidden = thicknessField.hidden && nameField.hidden;

  const points = data.points || [];
  const showHeading = data.format === 'v4';

  count.textContent = points.length;
  list.replaceChildren(
    ...points.map((p, i) => row(p, i + 1, points.length, isZone, showHeading, offset))
  );
  empty.hidden = points.length > 0;

  zValue.textContent = `${offset >= 0 ? '+' : ''}${offset.toFixed(2)}`;
  zValue.classList.toggle('lifted', Math.abs(offset) > 0.001);

  if (document.activeElement !== thickness) thickness.value = data.thickness;
  if (document.activeElement !== nameInput) nameInput.value = data.name || '';

  snippet.textContent = data.snippet || data.hint || '';
  snippet.classList.toggle('hint-only', !data.snippet);
}

function renderControls(data) {
  controlsTitle.textContent = data.title || '';
  controlsList.replaceChildren();

  (data.items || []).forEach((item) => {
    const dt = el('dt');
    (item.keys || []).forEach((key) => dt.append(el('kbd', null, key)));
    controlsList.append(dt, el('dd', null, item.label || ''));
  });

  controls.hidden = false;
}

function renderStatus(data) {
  statusFormat.textContent = data.format || '';

  const hasDistance = data.distance !== undefined && data.distance !== null;
  statusDistance.textContent = hasDistance ? `${data.distance.toFixed(1)} m` : '';

  statusTarget.textContent = data.target || '';
  statusTarget.className = data.kind || '';

  // Only shown when the collision ground actually disagrees with the probe,
  // so a visible line always means something happened.
  const snapped = data.snap !== undefined && data.snap !== null;
  statusSnap.hidden = !snapped;
  if (snapped) {
    statusSnap.textContent = `ground ${data.snap >= 0 ? '+' : ''}${data.snap.toFixed(2)} m`;
  }

  statusCard.hidden = false;
}

window.addEventListener('message', ({ data }) => {
  switch (data.type) {
    case 'zone:open':
      panel.hidden = false;
      break;
    case 'zone:close':
      panel.hidden = true;
      document.body.classList.remove('focused');
      break;
    case 'zone:focus':
      document.body.classList.toggle('focused', !!data.focused);
      break;
    case 'zone:data':
      render(data);
      break;
    case 'controls':
      renderControls(data);
      break;
    case 'controls:hide':
      controls.hidden = true;
      break;
    case 'status':
      renderStatus(data);
      break;
    case 'status:hide':
      statusCard.hidden = true;
      break;
  }
});

// Escape and G both hand the mouse back. Without this the only way out of the
// panel would be to click something, and the camera would just sit there.
// Typing a G into the name box must not eject you, hence the field check.
window.addEventListener('keydown', (event) => {
  const typing = /^(INPUT|TEXTAREA)$/.test(event.target.tagName);
  if (event.key === 'Escape' || (!typing && event.key.toLowerCase() === 'g')) {
    event.preventDefault();
    post('zone:blur');
  }
});

document.querySelectorAll('.formats button').forEach((button) => {
  button.addEventListener('click', () => post('zone:format', { format: button.dataset.format }));
});

document.getElementById('copy').addEventListener('click', () => post('zone:copy'));
document.getElementById('clear').addEventListener('click', () => post('zone:clear'));
document.getElementById('close').addEventListener('click', () => post('zone:close'));

thickness.addEventListener('change', () => {
  post('zone:thickness', { thickness: parseFloat(thickness.value) });
});

nameInput.addEventListener('change', () => post('zone:name', { name: nameInput.value }));

// The scroll wheel does this in game; these are the same action for when the
// panel already has the mouse. Lua clamps and echoes the result back, so the
// value here is only ever a starting point for the next nudge.
function nudgeZ(direction) {
  const current = parseFloat(zValue.textContent) || 0;
  post('zone:zoffset', { zOffset: current + direction * Z_STEP });
}

document.getElementById('z-up').addEventListener('click', () => nudgeZ(1));
document.getElementById('z-down').addEventListener('click', () => nudgeZ(-1));
document.getElementById('z-reset').addEventListener('click', () => post('zone:zoffset', { zOffset: 0 }));
