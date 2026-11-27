/* Browser adaptations only; all application screens are rendered by Flutter. */
(() => {
  let audio, interval, callback;
  const unlock = () => {
    try { audio ||= new (window.AudioContext || window.webkitAudioContext)(); audio.resume().catch(() => {}); } catch {}
  };
  document.addEventListener('pointerdown', unlock);
  document.addEventListener('keydown', unlock);
  const beep = () => {
    if (audio?.state !== 'running') return;
    for (let i = 0; i < 4; i++) {
      const oscillator = audio.createOscillator(), gain = audio.createGain();
      const start = audio.currentTime + i * .24;
      oscillator.type = 'square'; oscillator.frequency.value = i % 2 ? 880 : 660;
      gain.gain.setValueAtTime(0, start); gain.gain.linearRampToValueAtTime(.08, start+.02); gain.gain.linearRampToValueAtTime(0, start+.19);
      oscillator.connect(gain); gain.connect(audio.destination); oscillator.start(start); oscillator.stop(start+.2);
      oscillator.onended = () => { oscillator.disconnect(); gain.disconnect(); };
    }
  };
  const pending = [];
  function deliver(data) {
    if (!data || !['lesson_ring','lesson_ring_retry','lesson_ring_manual','teacher_ring'].includes(data.type)) return;
    if (callback) callback(JSON.stringify(data)); else pending.push(data);
  }
  navigator.serviceWorker?.addEventListener('message', event => { if (event.data?.type === 'yara-ring') deliver(event.data.data); });
  window.yaraWeb = {
    initialize(fn) { callback = fn; pending.splice(0).forEach(deliver); },
    playRing() { clearInterval(interval); beep(); interval = setInterval(beep, 1800); },
    stopRing() { clearInterval(interval); interval = null; },
    legacyToken() { try { return localStorage.getItem('ya_token') || null; } catch { return null; } },
    legacyDeviceId() { try { return localStorage.getItem('ya_dev') || null; } catch { return null; } },
    clearLegacyToken() { try { localStorage.removeItem('ya_token'); document.cookie = 'ya_t=; path=/; max-age=0; SameSite=Lax'; } catch {} },
  };
  try {
    const url = new URL(location.href), alert = url.searchParams.get('lessonAlert');
    if (alert) { deliver(JSON.parse(alert)); url.searchParams.delete('lessonAlert'); history.replaceState(null, '', url); }
  } catch {}
  window.addEventListener('flutter-first-frame', () => document.getElementById('yara-loading')?.remove());
})();
