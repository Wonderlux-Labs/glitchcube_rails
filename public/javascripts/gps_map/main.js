// GPS Map Main Initialization
window.GPSMap = window.GPSMap || {};

// Initialize everything when DOM is ready
document.addEventListener('DOMContentLoaded', async function() {
  const statusEl = document.getElementById('connectionStatus');
  const dotEl = document.getElementById('connectionDot');
  
  try {
    console.log('🔥 Starting GPS Map initialization...');
    
    // Initialize map
    GPSMap.MapSetup.init();
    console.log('✅ Map initialized');
    
    // Force map resize after layout changes
    setTimeout(() => {
      if (GPSMap.MapSetup.map) {
        GPSMap.MapSetup.map.invalidateSize();
        console.log('✅ Map size invalidated');
      }
    }, 100);
    
    // Initialize control handlers
    GPSMap.Controls.init();
    console.log('✅ Controls initialized');
    
    // Load only initial critical features (trash fence + major landmarks)
    try {
      await GPSMap.API.loadInitialData();
      console.log('✅ Initial features loaded');
    } catch (error) {
      console.log('⚠️ Initial features failed:', error.message);
    }
    
    // Load route history
    try {
      await GPSMap.API.loadRouteHistory();
      console.log('✅ Route history loaded');
    } catch (error) {
      console.log('⚠️ Route history failed:', error.message);
    }
    
    // Load home location
    try {
      await GPSMap.API.loadHomeLocation();
      console.log('✅ Home location loaded');
    } catch (error) {
      console.log('⚠️ Home location failed:', error.message);
    }
    
    // Initial location update (this is the most critical)
    await GPSMap.API.updateLocation();
    console.log('✅ Initial location updated');
    
    if (statusEl) {
      statusEl.textContent = 'GPS tracking active!';
      statusEl.className = 'indicator-text connected';
    }
    if (dotEl) {
      dotEl.className = 'indicator-dot connected';
    }
    
    // Update location every X seconds
    setInterval(() => {
      GPSMap.API.updateLocation();
    }, window.APP_CONFIG.updateInterval);
    
    console.log('🔥 GPS Map initialization complete!');
    console.log('Tracking via Home Assistant device tracker');
    console.log('Streets, landmarks, and toilets load on-demand via toggles');
    
  } catch (error) {
    console.error('❌ Initialization failed:', error);
    if (statusEl) {
      statusEl.textContent = 'Initialization failed: ' + error.message;
      statusEl.className = 'indicator-text offline';
    }
    if (dotEl) {
      dotEl.className = 'indicator-dot offline';
    }
    
    // Update panel with offline status
    if (typeof GPSMap.API.updateInformationPanelOffline === 'function') {
      GPSMap.API.updateInformationPanelOffline();
    }
  }
});