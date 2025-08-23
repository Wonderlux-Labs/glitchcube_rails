// GPS Map Icon Factory
window.GPSMap = window.GPSMap || {};

GPSMap.Icons = {
  _uniqueIdCounter: 0,
  
  // Generate unique ID for SVG elements
  _getUniqueId: function(base) {
    return `${base}_${++this._uniqueIdCounter}_${Date.now()}`;
  },
  
  // Create custom icon for different marker types
  createCustomIcon: function(type, size) {
    size = size || 32;
    
    // Generate unique IDs for this icon instance
    const cubeGradId = this._getUniqueId('cubeGrad');
    const glowId = this._getUniqueId('glow');
    const homeGradId = this._getUniqueId('homeGrad');
    const templeGradId = this._getUniqueId('templeGrad');
    const manGradId = this._getUniqueId('manGrad');
    const fireGlowId = this._getUniqueId('fireGlow');
    const medGradId = this._getUniqueId('medGrad');
    const rangerGradId = this._getUniqueId('rangerGrad');
    const artGradId = this._getUniqueId('artGrad');
    
    const icons = {
      cube: {
        svg: `<svg viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
          <defs>
            <radialGradient id="${cubeGradId}" cx="50%" cy="30%">
              <stop offset="0%" style="stop-color:#ffaa66;stop-opacity:1" />
              <stop offset="100%" style="stop-color:#ff6b35;stop-opacity:1" />
            </radialGradient>
            <filter id="${glowId}">
              <feGaussianBlur stdDeviation="2" result="coloredBlur"/>
              <feMerge> 
                <feMergeNode in="coloredBlur"/>
                <feMergeNode in="SourceGraphic"/>
              </feMerge>
            </filter>
          </defs>
          <circle cx="16" cy="16" r="14" fill="url(#${cubeGradId})" stroke="#fff" stroke-width="2" filter="url(#${glowId})"/>
          <path d="M8 12 L16 8 L24 12 L24 20 L16 24 L8 20 Z" fill="none" stroke="#1a0d00" stroke-width="2"/>
          <path d="M8 12 L16 16 L24 12 M16 16 L16 24" fill="none" stroke="#1a0d00" stroke-width="2"/>
        </svg>`,
        className: 'cube-marker pulse',
        color: '#ff8c42'
      },
      home: {
        svg: `<svg viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
          <defs>
            <linearGradient id="${homeGradId}" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" style="stop-color:#ffdd44;stop-opacity:1" />
              <stop offset="100%" style="stop-color:#ffaa00;stop-opacity:1" />
            </linearGradient>
          </defs>
          <circle cx="16" cy="16" r="14" fill="url(#${homeGradId})" stroke="#fff" stroke-width="2"/>
          <path d="M8 18 L16 10 L24 18 L22 18 L22 24 L10 24 L10 18 Z" fill="#1a0d00"/>
          <rect x="13" y="20" width="6" height="4" fill="#ffdd44"/>
        </svg>`,
        className: 'home-marker',
        color: '#ffaa00'
      },
      temple: {
        svg: `<svg viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
          <!-- Clean temple silhouette -->
          <g fill="#8B7355" stroke="#654321" stroke-width="1">
            <!-- Temple roof -->
            <path d="M6 20 L16 8 L26 20 L24 20 L24 24 L8 24 L8 20 Z"/>
            <!-- Columns -->
            <rect x="10" y="12" width="2" height="12"/>
            <rect x="15" y="12" width="2" height="12"/>
            <rect x="20" y="12" width="2" height="12"/>
            <!-- Base -->
            <rect x="7" y="24" width="18" height="2" rx="1"/>
          </g>
        </svg>`,
        className: 'temple-marker sacred-glow',
        color: '#8B7355'
      },
      man: {
        svg: `<svg viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
          <!-- Iconic Burning Man silhouette -->
          <g transform="translate(16,16) scale(1.0) translate(-16,-16)" fill="#8B4513" stroke="#654321" stroke-width="1">
            <!-- Head -->
            <circle cx="16" cy="7" r="2"/>
            <!-- Body/torso -->
            <rect x="14.5" y="9" width="3" height="8" rx="0.5"/>
            <!-- Arms raised high and wide -->
            <line x1="14.5" y1="11" x2="10" y2="5" stroke-width="2" stroke-linecap="round"/>
            <line x1="17.5" y1="11" x2="22" y2="5" stroke-width="2" stroke-linecap="round"/>
            <!-- Legs spread -->
            <line x1="15" y1="17" x2="12" y2="23" stroke-width="2" stroke-linecap="round"/>
            <line x1="17" y1="17" x2="20" y2="23" stroke-width="2" stroke-linecap="round"/>
            <!-- Base/platform -->
            <rect x="10" y="23" width="12" height="2" rx="1" fill="#654321"/>
          </g>
        </svg>`,
        className: 'man-marker beacon-effect',
        color: '#8B4513'
      },
      medical: {
        svg: `<svg viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
          <defs>
            <linearGradient id="${medGradId}" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" style="stop-color:#ff6666;stop-opacity:1" />
              <stop offset="100%" style="stop-color:#cc0000;stop-opacity:1" />
            </linearGradient>
          </defs>
          <circle cx="16" cy="16" r="14" fill="url(#${medGradId})" stroke="#fff" stroke-width="2"/>
          <path d="M12 16 L20 16 M16 12 L16 20" stroke="#fff" stroke-width="4"/>
        </svg>`,
        className: 'medical-marker emergency-pulse',
        color: '#ff0000'
      },
      ranger: {
        svg: `<svg viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
          <defs>
            <linearGradient id="${rangerGradId}" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" style="stop-color:#4488ff;stop-opacity:1" />
              <stop offset="100%" style="stop-color:#0066cc;stop-opacity:1" />
            </linearGradient>
          </defs>
          <circle cx="16" cy="16" r="14" fill="url(#${rangerGradId})" stroke="#fff" stroke-width="2"/>
          <polygon points="16,6 20,14 12,14" fill="#fff"/>
          <rect x="14" y="14" width="4" height="6" fill="#fff"/>
          <circle cx="16" cy="22" r="2" fill="#fff"/>
        </svg>`,
        className: 'ranger-marker',
        color: '#4488ff'
      },
      art: {
        svg: `<svg viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
          <defs>
            <linearGradient id="${artGradId}" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" style="stop-color:#ff88ff;stop-opacity:1" />
              <stop offset="100%" style="stop-color:#cc44cc;stop-opacity:1" />
            </linearGradient>
          </defs>
          <circle cx="16" cy="16" r="14" fill="url(#${artGradId})" stroke="#fff" stroke-width="2"/>
          <polygon points="16,8 20,12 16,16 12,12" fill="#fff"/>
          <polygon points="16,16 20,20 16,24 12,20" fill="#fff" opacity="0.7"/>
        </svg>`,
        className: 'art-marker creative-pulse',
        color: '#ff88ff'
      }
    };
    
    const config = icons[type] || icons.cube;
    return L.divIcon({
      className: `custom-marker ${config.className}`,
      html: `<div style="width: ${size}px; height: ${size}px; filter: drop-shadow(0 2px 8px rgba(0,0,0,0.4));">${config.svg}</div>`,
      iconSize: [size, size],
      iconAnchor: [size/2, size/2]
    });
  },

  // Create simple landmark icon  
  createLandmarkIcon: function(type, size) {
    size = size || 16; // Smaller default size
    const icons = {
      'center': '🔥',
      'sacred': '🏛️', 
      'medical': '🏥',
      'toilet': '🚻',
      'art': '🎨',
      'service': '⚙️',
      'gathering': '●', // Simple dot instead of tent
      'plaza': '🏛️',
      'poi': '●', // Simple dot instead of red pin
      'transport': '🚌',
      'ranger': '👮'
    };
    
    const emoji = icons[type] || '●'; // Use simple dot as default
    
    return L.divIcon({
      className: 'landmark-icon',
      html: `<div style="font-size: ${Math.floor(size * 0.7)}px; text-align: center; color: #666; text-shadow: 1px 1px 1px rgba(255,255,255,0.8);">${emoji}</div>`,
      iconSize: [size, size],
      iconAnchor: [size/2, size/2]
    });
  }
};