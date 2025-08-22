// GPS Map Controls Handler
window.GPSMap = window.GPSMap || {};

GPSMap.Controls = {
  // Simple control states
  showRoute: false,
  showLandmarks: true, // Everything loaded by default except toilets
  showToilets: false,
  
  
  // Initialize control handlers
  init: function() {
    this.initRouteToggle();
    this.initLandmarksToggle();
    this.initToiletsToggle();
    this.initCenterButton();
  },
  
  initRouteToggle: function() {
    const btn = document.getElementById('routeToggle');
    if (!btn) return;
    
    btn.addEventListener('click', () => {
      this.showRoute = !this.showRoute;
      const showing = GPSMap.Markers.toggleRouteHistory();
      btn.classList.toggle('active', showing);
      btn.textContent = showing ? 'HIDE route' : 'SHOW route';
    });
  },
  
  initLandmarksToggle: function() {
    const btn = document.getElementById('landmarksToggle');
    if (!btn) return;
    
    // Set initial state - landmarks shown by default
    btn.classList.add('active');
    
    btn.addEventListener('click', () => {
      this.showLandmarks = !this.showLandmarks;
      btn.classList.toggle('active', this.showLandmarks);
      btn.textContent = this.showLandmarks ? 'HIDE landmarks' : 'SHOW landmarks';
      
      if (this.showLandmarks) {
        GPSMap.MapSetup.layers.landmarks.addTo(GPSMap.MapSetup.map);
      } else {
        GPSMap.MapSetup.map.removeLayer(GPSMap.MapSetup.layers.landmarks);
      }
    });
  },
  
  initToiletsToggle: function() {
    const btn = document.getElementById('portosToggle');
    if (!btn) return;
    
    btn.addEventListener('click', async () => {
      this.showToilets = !this.showToilets;
      btn.classList.toggle('active', this.showToilets);
      btn.textContent = this.showToilets ? 'HIDE toilets' : 'SHOW toilets';
      
      if (this.showToilets) {
        // Load toilets on demand
        btn.textContent = 'Loading...';
        await GPSMap.API.loadToiletsNearby();
        btn.textContent = 'HIDE toilets';
        if (GPSMap.MapSetup.layers.toilets) {
          GPSMap.MapSetup.layers.toilets.addTo(GPSMap.MapSetup.map);
        }
      } else {
        if (GPSMap.MapSetup.layers.toilets) {
          GPSMap.MapSetup.map.removeLayer(GPSMap.MapSetup.layers.toilets);
        }
      }
    });
  },
  
  initCenterButton: function() {
    const btn = document.getElementById('centerToggle');
    if (!btn) return;
    
    btn.addEventListener('click', () => {
      GPSMap.Markers.centerOnCube();
    });
  }
};