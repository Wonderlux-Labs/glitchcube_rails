// GPS Map Controls Handler
window.GPSMap = window.GPSMap || {};

GPSMap.Controls = {
  // Simple control states
  showRoute: false,
  showLandmarks: true, // Everything loaded by default except toilets
  showToilets: false,
  
  
  // Initialize control handlers
  init: function() {
    this.initCenterButton();
    this.initLandmarksToggle();
    this.initStreetsToggle();
    this.initCompassButton();
  },
  
  initCenterButton: function() {
    const btn = document.getElementById('center-button');
    if (!btn) return;
    
    btn.addEventListener('click', () => {
      if (GPSMap.Markers && GPSMap.Markers.centerOnCube) {
        GPSMap.Markers.centerOnCube();
      }
    });
  },
  
  initLandmarksToggle: function() {
    const btn = document.getElementById('landmarks-toggle');
    if (!btn) return;
    
    // Set initial state - landmarks shown by default
    btn.classList.add('active');
    
    btn.addEventListener('click', () => {
      this.showLandmarks = !this.showLandmarks;
      btn.classList.toggle('active', this.showLandmarks);
      
      if (this.showLandmarks) {
        GPSMap.MapSetup.layers.landmarks.addTo(GPSMap.MapSetup.map);
      } else {
        GPSMap.MapSetup.map.removeLayer(GPSMap.MapSetup.layers.landmarks);
      }
    });
  },
  
  initStreetsToggle: function() {
    const btn = document.getElementById('streets-toggle');
    if (!btn) return;
    
    btn.addEventListener('click', () => {
      // Streets are disabled - this button doesn't do anything
      console.log('Streets are disabled - fragments only in database');
    });
  },
  
  initCompassButton: function() {
    const btn = document.getElementById('compass-button');
    if (!btn) return;
    
    btn.addEventListener('click', () => {
      GPSMap.MapSetup.centerOnGoldenSpike();
    });
  }
};