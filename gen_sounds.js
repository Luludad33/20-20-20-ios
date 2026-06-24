const fs = require('fs');
const path = require('path');

function writeWAV(filePath, samples, sampleRate = 44100) {
  const numChannels = 1;
  const bitsPerSample = 16;
  const byteRate = sampleRate * numChannels * bitsPerSample / 8;
  const blockAlign = numChannels * bitsPerSample / 8;
  const dataSize = samples.length * blockAlign;

  const buf = Buffer.alloc(44 + dataSize);
  // RIFF header
  buf.write('RIFF', 0);
  buf.writeUInt32LE(36 + dataSize, 4);
  buf.write('WAVE', 8);
  // fmt chunk
  buf.write('fmt ', 12);
  buf.writeUInt32LE(16, 16);        // chunk size
  buf.writeUInt16LE(1, 20);         // PCM
  buf.writeUInt16LE(numChannels, 22);
  buf.writeUInt32LE(sampleRate, 24);
  buf.writeUInt32LE(byteRate, 28);
  buf.writeUInt16LE(blockAlign, 32);
  buf.writeUInt16LE(bitsPerSample, 34);
  // data chunk
  buf.write('data', 36);
  buf.writeUInt32LE(dataSize, 40);
  for (let i = 0; i < samples.length; i++) {
    const val = Math.max(-32767, Math.min(32767, Math.round(samples[i] * 32767)));
    buf.writeInt16LE(val, 44 + i * 2);
  }
  fs.writeFileSync(filePath, buf);
}

const sr = 44100;

// alert.wav — two ascending tones, ~1.2s, fade out
const alertSamples = [];
for (let i = 0; i < sr * 1.2; i++) {
  const t = i / sr;
  const env = Math.max(0, 1 - t / 1.2);
  const freq = t < 0.6 ? 660 : 880;
  let val = env * 0.8 * Math.sin(2 * Math.PI * freq * t);
  val += env * 0.3 * Math.sin(2 * Math.PI * freq * 2 * t);
  alertSamples.push(val * 0.5);
}
writeWAV('alert.wav', alertSamples);

// complete.wav — short descending chime, ~0.4s
const compSamples = [];
for (let i = 0; i < sr * 0.4; i++) {
  const t = i / sr;
  const env = Math.exp(-t * 5);
  const freq = 880 - 220 * (t / 0.4);
  const val = env * Math.sin(2 * Math.PI * freq * t);
  compSamples.push(val * 0.5);
}
writeWAV('complete.wav', compSamples);

console.log('OK', fs.statSync('alert.wav').size, fs.statSync('complete.wav').size);
