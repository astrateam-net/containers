#!/usr/bin/env node
/**
 * Runtime patch for penpot-plugin to replace hardcoded WebSocket URL
 * Replaces ws://localhost:4402/ with wss:// based on current origin
 * This allows the plugin to connect via the same domain (HTTPS) as the plugin page
 */

const fs = require('fs');
const path = require('path');

const pluginDistDir = '/app/penpot-plugin/dist';

// Patterns to match WebSocket URLs in different contexts
// Pattern 1: String literal in new WebSocket("ws://localhost:4402")
// Pattern 2: Template string `ws://localhost:4402`
// Pattern 3: Just the URL string
const patterns = [
  {
    // Match: new WebSocket("ws://localhost:4402")
    // Replace with: new WebSocket(`wss://${window.location.host}/ws`)
    pattern: /new\s+WebSocket\s*\(\s*["']ws:\/\/localhost:4402\/?["']\s*\)/g,
    replacement: `new WebSocket(\`wss://\${window.location.host}/ws\`)`
  },
  {
    // Match: "ws://localhost:4402" or 'ws://localhost:4402'
    pattern: /["']ws:\/\/localhost:4402\/?["']/g,
    replacement: '`wss://${window.location.host}/ws`'
  },
  {
    // Match: `ws://localhost:4402`
    pattern: /`ws:\/\/localhost:4402\/?`/g,
    replacement: '`wss://${window.location.host}/ws`'
  }
];

function patchFiles(dir) {
  const files = fs.readdirSync(dir);
  let patchedCount = 0;
  
  for (const file of files) {
    const filePath = path.join(dir, file);
    const stat = fs.statSync(filePath);
    
    if (stat.isDirectory()) {
      patchedCount += patchFiles(filePath);
    } else if (file.endsWith('.js')) {
      let content = fs.readFileSync(filePath, 'utf8');
      const originalContent = content;
      
      // Try all patterns
      for (const { pattern, replacement } of patterns) {
        content = content.replace(pattern, replacement);
      }
      
      if (content !== originalContent) {
        fs.writeFileSync(filePath, content, 'utf8');
        console.log(`Patched: ${filePath}`);
        patchedCount++;
      }
    }
  }
  
  return patchedCount;
}

console.log('Patching penpot-plugin WebSocket URLs...');
console.log('Replacing ws://localhost:4402/ with: wss://${window.location.host}/ws');

if (fs.existsSync(pluginDistDir)) {
  const count = patchFiles(pluginDistDir);
  if (count > 0) {
    console.log(`✓ Patched ${count} file(s)`);
  } else {
    console.log('⚠ No files needed patching (pattern not found)');
  }
} else {
  console.error(`✗ Plugin dist directory not found: ${pluginDistDir}`);
  process.exit(1);
}

