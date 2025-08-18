// GPS Map Main Initialization
window.GPSMap = window.GPSMap || {};

// Initialize everything when DOM is ready
document.addEventListener('DOMContentLoaded', async function() {
  const statusEl = document.getElementById('status');
  
  try {
    console.log('🔥 Starting GPS Map initialization...');
    
    // Initialize map
    GPSMap.MapSetup.init();
    console.log('✅ Map initialized');
    
    // Initialize control handlers
    GPSMap.Controls.init();
    console.log('✅ Controls initialized');
    
    // Load only initial critical features (trash fence + major landmarks)
    await GPSMap.API.loadInitialData();
    console.log('✅ Initial features loaded');
    
    // Load route history
    await GPSMap.API.loadRouteHistory();
    console.log('✅ Route history loaded');
    
    // Load home location
    await GPSMap.API.loadHomeLocation();
    console.log('✅ Home location loaded');
    
    // Initial location update
    await GPSMap.API.updateLocation();
    console.log('✅ Initial location updated');
    
    statusEl.textContent = 'GPS tracking active!';
    statusEl.className = 'status-display';
    
    // Update location every X seconds
    setInterval(() => {
      GPSMap.API.updateLocation();
    }, window.APP_CONFIG.updateInterval);
    
    console.log('🔥 GPS Map initialization complete!');
    console.log('Tracking via Home Assistant device tracker');
    console.log('Streets, landmarks, and toilets load on-demand via toggles');
    
  } catch (error) {
    console.error('❌ Initialization failed:', error);
    statusEl.textContent = 'Initialization failed: ' + error.message;
    statusEl.className = 'status-display offline';
  }
});