// GPS Map API Calls
window.GPSMap = window.GPSMap || {};

GPSMap.API = {
  // Update location from API
  updateLocation: async function() {
    const statusEl = document.getElementById('status');
    
    try {
      const response = await fetch(window.APP_CONFIG.api.locationEndpoint);
      const data = await response.json();
      
      if (data.lat && data.lng) {
        // Update cube marker with full location context
        GPSMap.Markers.updateCubeMarker(data.lat, data.lng, data);
        
        // Update info panels
        this.updateInfoPanels(data);
        
        // Update landmark proximity
        GPSMap.Landmarks.updateLandmarkProximity({ lat: data.lat, lng: data.lng });
        
        // Check for nearby landmarks
        const nearbyLandmarks = GPSMap.Landmarks.getNearbyLandmarks(data.lat, data.lng);
        this.updateProximityAlert(nearbyLandmarks);
        
        // Add to route history
        GPSMap.Markers.addToRouteHistory(data.lat, data.lng, data.timestamp, data.address);
        
        statusEl.textContent = `Last updated: ${new Date(data.timestamp).toLocaleTimeString()}`;
        statusEl.className = 'status-display';
      } else {
        throw new Error('Invalid location data');
      }
    } catch (error) {
      console.error('Error fetching location:', error);
      statusEl.textContent = 'Connection lost - retrying...';
      statusEl.className = 'status-display offline';
    }
  },
  
  // Update info panels with location data
  updateInfoPanels: function(data) {
    const addressBar = document.getElementById('addressBar');
    const sectionBar = document.getElementById('sectionBar');
    const distanceBar = document.getElementById('distanceBar');
    const coordinatesEl = document.getElementById('coordinates');
    const simModeIndicator = document.getElementById('simModeIndicator');
    
    // Update address - prioritize street address over landmark name
    let addressStr = '';
    if (data.address) {
      addressStr = data.address;
      // Add landmark context if available
      if (data.landmark_name && data.landmark_name !== data.address) {
        addressStr += ` (Near ${data.landmark_name})`;
      }
    } else if (data.landmark_name) {
      addressStr = data.landmark_name;
    } else {
      addressStr = 'Black Rock City';
    }
    addressBar.textContent = addressStr;
    
    // Update section and coordinates
    sectionBar.textContent = data.section || '';
    coordinatesEl.textContent = `${data.lat?.toFixed(6) ?? ''}, ${data.lng?.toFixed(6) ?? ''}`;
    distanceBar.textContent = data.distance_from_man || '';
    
    // Show simulation mode indicator
    if (data.source === 'simulation') {
      simModeIndicator.textContent = 'SIMULATION MODE';
    } else {
      simModeIndicator.textContent = '';
    }
  },
  
  // Update proximity alert
  updateProximityAlert: function(nearbyLandmarks) {
    const existingAlert = document.getElementById('proximity-alert');
    if (existingAlert) existingAlert.remove();
    
    if (nearbyLandmarks.length > 0) {
      const nearest = nearbyLandmarks[0];
      const distance = Math.round(GPSMap.Utils.haversineDistance(
        GPSMap.Markers.cubeMarker.getLatLng().lat,
        GPSMap.Markers.cubeMarker.getLatLng().lng,
        nearest.lat, nearest.lng
      ));
      
      const alertEl = document.createElement('div');
      alertEl.id = 'proximity-alert';
      alertEl.textContent = `⚠️ Near ${nearest.name} (${distance}m)`;
      alertEl.style.cssText = 'color: #39ff14; font-size: 12px; margin-top: 5px; background: rgba(57, 255, 20, 0.1); padding: 3px; border-radius: 3px;';
      document.getElementById('addressBar').parentNode.appendChild(alertEl);
    }
  },
  
  // Load route history
  loadRouteHistory: async function() {
    try {
      const response = await fetch(window.APP_CONFIG.api.historyEndpoint);
      const data = await response.json();
      
      if (data.history && data.history.length > 0) {
        GPSMap.Markers.routeHistory = data.history.map(point => ({
          lat: point.lat,
          lng: point.lng,
          timestamp: point.timestamp,
          address: point.address
        }));
        
        console.log(`Loaded ${GPSMap.Markers.routeHistory.length} route points`);
      }
    } catch (error) {
      console.error('Error loading route history:', error);
    }
  },
  
  // City blocks data available but not displayed on map
  // Backend uses this for zone determination only
  loadCityBlocks: async function() {
    // City blocks are used by backend only for zone determination
    // Not displayed on frontend map per requirements
    console.log('City blocks available for backend zone calculations only');
  },
  
  // Load initial critical features only
  loadInitialData: async function() {
    try {
      // Load city blocks first
      await this.loadCityBlocks();
      
      // Inner Playa boundary data available for backend calculations
      // Not displayed on map per requirements
      try {
        const zonesResponse = await fetch('/api/v1/gis/zones');
        const zonesData = await zonesResponse.json();
        
        if (zonesData.features) {
          // Store inner playa boundary data for backend use
          // This is the 0.47 mi radius from The Man
          zonesData.features.forEach(feature => {
            if (feature.geometry.type === 'Polygon') {
              // Store boundary data but don't display it
              if (feature.properties.zone_type === 'inner_playa') {
                // Available for backend zone calculations
                console.log('Inner Playa boundary (0.47mi) loaded for backend use');
              }
            }
          });
          // Zone boundary data loaded for backend use only
          console.log('Zone boundaries loaded for backend calculations');
        }
      } catch (zoneError) {
        console.log('Zone boundaries not available:', zoneError);
      }
      
      const response = await fetch('/api/v1/gis/initial');
      const data = await response.json();
      
      if (data.features) {
        data.features.forEach(feature => {
          if (feature.properties.feature_type === 'boundary') {
            // Add trash fence
            if (feature.geometry.type === 'Polygon') {
              const coords = feature.geometry.coordinates[0].map(coord => [coord[1], coord[0]]);
              L.polygon(coords, {
                color: '#FF6B6B',
                fillColor: 'transparent',
                fillOpacity: 0,
                weight: 2,
                dashArray: '10, 5',
                interactive: false // Don't intercept clicks
              }).addTo(GPSMap.MapSetup.layers.boundaries);
            }
          } else if (feature.properties.feature_type === 'major_landmark') {
            // Add major landmarks (Man, Temple, Center Camp)
            const lat = feature.geometry.coordinates[1];
            const lng = feature.geometry.coordinates[0];
            
            // Use custom SVG icons for special landmarks
            let icon;
            if (feature.properties.landmark_type === 'center') {
              icon = GPSMap.Icons.createCustomIcon('man', 32);
            } else if (feature.properties.landmark_type === 'sacred') {
              icon = GPSMap.Icons.createCustomIcon('temple', 32);
            } else {
              icon = GPSMap.Icons.createLandmarkIcon(feature.properties.landmark_type, 32);
            }
            
            L.marker([lat, lng], { icon: icon })
              .addTo(GPSMap.MapSetup.layers.landmarks)
              .bindPopup(`<strong>${feature.properties.name}</strong>`);
          } else if (feature.properties.feature_type === 'landmark') {
            // Add all other landmarks (plazas, medical, art, etc.)
            const lat = feature.geometry.coordinates[1];
            const lng = feature.geometry.coordinates[0];
            
            // Use custom icons for special landmarks, emoji for others
            let icon;
            if (feature.properties.landmark_type === 'center') {
              icon = GPSMap.Icons.createCustomIcon('man', 20);
            } else if (feature.properties.landmark_type === 'sacred') {
              icon = GPSMap.Icons.createCustomIcon('temple', 20);
            } else {
              icon = GPSMap.Icons.createLandmarkIcon(feature.properties.landmark_type, 20);
            }
            
            L.marker([lat, lng], { icon: icon })
              .addTo(GPSMap.MapSetup.layers.landmarks)
              .bindPopup(`<strong>${feature.properties.name}</strong>`);
          }
        });
        console.log(`✅ Loaded ${data.count} initial features`);
      }
    } catch (error) {
      console.error('Error loading initial data:', error);
    }
  },
  
  // Load toilets near current location
  loadToiletsNearby: async function() {
    try {
      let lat, lng;
      
      // Use cube location if available
      if (GPSMap.Markers.cubeMarker) {
        const pos = GPSMap.Markers.cubeMarker.getLatLng();
        lat = pos.lat;
        lng = pos.lng;
      } else {
        // Use map center
        const center = GPSMap.MapSetup.map.getCenter();
        lat = center.lat;
        lng = center.lng;
      }
      
      const params = new URLSearchParams({
        lat: lat,
        lng: lng,
        radius: 1000 // 1km radius for toilets
      });
      
      // Create a new layer group for toilets if it doesn't exist
      if (!GPSMap.MapSetup.layers.toilets) {
        GPSMap.MapSetup.layers.toilets = L.layerGroup();
      }
      
      // Clear existing toilets
      GPSMap.MapSetup.layers.toilets.clearLayers();
      
      const response = await fetch(`/api/v1/gis/landmarks/nearby?${params}`);
      const data = await response.json();
      
      if (data.landmarks) {
        // Filter for toilets only
        const toilets = data.landmarks.filter(l => l.type === 'toilet');
        
        toilets.forEach(toilet => {
          L.marker([toilet.lat, toilet.lng], {
            icon: L.divIcon({
              className: 'toilet-marker',
              html: '🚽',
              iconSize: [20, 20]
            })
          }).addTo(GPSMap.MapSetup.layers.toilets)
            .bindPopup(toilet.name || 'Portable Toilet');
        });
        console.log(`Loaded ${toilets.length} nearby toilets`);
      }
    } catch (error) {
      console.error('Error loading toilets:', error);
    }
  },
  
  // Load home location
  loadHomeLocation: async function() {
    try {
      const response = await fetch(window.APP_CONFIG.api.homeEndpoint);
      const homeData = await response.json();
      
      if (homeData.lat && homeData.lng) {
        GPSMap.Markers.addHomeMarker(homeData.lat, homeData.lng, homeData.address);
      }
    } catch (error) {
      console.error('Error loading home location:', error);
    }
  }
};