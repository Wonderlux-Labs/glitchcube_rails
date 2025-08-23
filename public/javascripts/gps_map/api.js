// GPS Map API Calls
window.GPSMap = window.GPSMap || {};

GPSMap.API = {
  // Update location from API
  updateLocation: async function() {
    const statusEl = document.getElementById('connectionStatus');
    const dotEl = document.getElementById('connectionDot');
    
    try {
      const response = await fetch(window.APP_CONFIG.api.locationEndpoint);
      const data = await response.json();
      
      if (data.lat && data.lng) {
        // Update cube marker with full location context
        if (GPSMap.Markers && typeof GPSMap.Markers.updateCubeMarker === 'function') {
          GPSMap.Markers.updateCubeMarker(data.lat, data.lng, data);
        } else {
          console.warn('GPSMap.Markers not available, skipping cube marker update');
        }
        
        // Update info panels
        this.updateInfoPanels(data);
        
        // Update landmark proximity using data from API response
        if (data.landmarks && data.landmarks.length > 0) {
          this.updateProximityAlert(data.landmarks);
          this.displayNearbyLandmarks(data.landmarks);
        } else {
          // Clear landmarks display if no landmarks nearby
          const existingAlert = document.getElementById('proximity-alert');
          const existingList = document.getElementById('landmarks-list');
          if (existingAlert) existingAlert.remove();
          if (existingList) existingList.remove();
        }
        
        // Add to route history
        if (GPSMap.Markers && typeof GPSMap.Markers.addToRouteHistory === 'function') {
          GPSMap.Markers.addToRouteHistory(data.lat, data.lng, data.timestamp, data.address);
        }
        
        if (statusEl) {
          statusEl.textContent = `Last updated: ${new Date(data.timestamp).toLocaleTimeString()}`;
          statusEl.className = 'indicator-text connected';
        }
        if (dotEl) {
          dotEl.className = 'indicator-dot connected';
        }
      } else {
        throw new Error('Invalid location data');
      }
    } catch (error) {
      console.error('Error fetching location:', error);
      if (statusEl) {
        statusEl.textContent = 'Connection lost - retrying...';
        statusEl.className = 'indicator-text offline';
      }
      if (dotEl) {
        dotEl.className = 'indicator-dot offline';
      }
      
      // Update panel with offline status
      this.updateInformationPanelOffline();
    }
  },
  
  // Update info panels with location data
  updateInfoPanels: function(data) {
    console.log('updateInfoPanels called with data:', data);
    
    const addressBar = document.getElementById('addressBar');
    const sectionBar = document.getElementById('sectionBar');
    // distanceBar no longer exists in new layout - info now in panel
    const coordinatesEl = document.getElementById('coordinates');
    const simModeIndicator = document.getElementById('simModeIndicator');
    
    // Get nearest landmark name from landmarks array
    let nearestLandmark = null;
    if (data.landmarks && data.landmarks.length > 0) {
      nearestLandmark = data.landmarks[0]; // First landmark is nearest
    }
    
    // Update address - show landmark name if very close (< 5 meters), otherwise show street address
    let addressStr = '';
    if (nearestLandmark && nearestLandmark.distance_meters < 5) {
      addressStr = nearestLandmark.name;
      if (data.address && data.address !== nearestLandmark.name) {
        addressStr += ` (${data.address})`;
      }
    } else if (data.address) {
      addressStr = data.address;
      if (nearestLandmark && nearestLandmark.distance_meters < 50) {
        addressStr += ` (Near ${nearestLandmark.name})`;
      }
    } else {
      addressStr = nearestLandmark ? nearestLandmark.name : 'Black Rock City';
    }
    
    console.log('Setting address to:', addressStr);
    if (addressBar) addressBar.textContent = addressStr;
    
    // Update zone and coordinates
    const zoneText = data.zone ? data.zone.toString().replace('_', ' ').toUpperCase() : '';
    console.log('Setting zone to:', zoneText, 'from data.zone:', data.zone);
    if (sectionBar) sectionBar.textContent = zoneText;
    if (coordinatesEl) coordinatesEl.textContent = `${data.lat?.toFixed(6) ?? ''}, ${data.lng?.toFixed(6) ?? ''}`;
    
    // Show simulation mode indicator
    if (simModeIndicator) {
      if (data.source === 'simulation') {
        simModeIndicator.textContent = 'SIMULATION MODE';
      } else if (data.source === 'random_landmark') {
        simModeIndicator.textContent = 'DEMO MODE';
      } else {
        simModeIndicator.textContent = '';
      }
    }
    
    // Update information panel
    this.updateInformationPanel(data);
  },
  
  // Update proximity alert
  updateProximityAlert: function(nearbyLandmarks) {
    const existingAlert = document.getElementById('proximity-alert');
    if (existingAlert) existingAlert.remove();
    
    if (nearbyLandmarks.length > 0) {
      const nearest = nearbyLandmarks[0];
      const distance = Math.round(nearest.distance_meters || 0);
      
      const alertEl = document.createElement('div');
      alertEl.id = 'proximity-alert';
      alertEl.textContent = `⚠️ Near ${nearest.name} (${distance}m)`;
      alertEl.style.cssText = 'color: #00ffff; font-size: 12px; margin-top: 5px; background: rgba(0, 255, 255, 0.1); padding: 3px 6px; border-radius: 3px; border: 1px solid rgba(0, 255, 255, 0.3);';
      document.getElementById('addressBar').parentNode.appendChild(alertEl);
    }
  },
  
  // Display nearby landmarks list
  displayNearbyLandmarks: function(landmarks) {
    let existingList = document.getElementById('landmarks-list');
    
    // Only show list if there are multiple landmarks
    if (landmarks.length <= 1) {
      if (existingList) existingList.remove();
      return;
    }
    
    // Generate current landmarks content
    let content = '<strong>📍 Nearby:</strong><br>';
    landmarks.slice(0, 5).forEach(landmark => {
      const distance = Math.round(landmark.distance_meters || 0);
      content += `• ${landmark.name} (${distance}m)<br>`;
    });
    
    // If list doesn't exist, create it
    if (!existingList) {
      const listEl = document.createElement('div');
      listEl.id = 'landmarks-list';
      listEl.style.cssText = 'position: absolute; top: 80px; right: 10px; background: rgba(0, 0, 0, 0.8); color: #00ffff; padding: 8px; border-radius: 4px; font-size: 11px; max-width: 200px; border: 1px solid rgba(0, 255, 255, 0.3); z-index: 1000;';
      
      // Add close button
      const closeBtn = document.createElement('span');
      closeBtn.innerHTML = '×';
      closeBtn.style.cssText = 'position: absolute; top: 2px; right: 5px; cursor: pointer; color: #ff6b6b; font-weight: bold; font-size: 14px;';
      closeBtn.onclick = () => listEl.remove();
      
      listEl.appendChild(closeBtn);
      listEl.innerHTML = content + listEl.innerHTML;
      document.body.appendChild(listEl);
      existingList = listEl;
    } else {
      // Update existing list content only if it has changed
      const currentContent = existingList.innerHTML;
      const newContentWithClose = content + '<span style="position: absolute; top: 2px; right: 5px; cursor: pointer; color: #ff6b6b; font-weight: bold; font-size: 14px;" onclick="this.parentElement.remove()">×</span>';
      
      if (!currentContent.includes(content.substring(0, 50))) { // Check if content is significantly different
        existingList.innerHTML = newContentWithClose;
      }
    }
  },
  
  // Update the information panel with location data
  updateInformationPanel: function(data) {
    // Update panel status elements
    const panelZone = document.getElementById('panelZone');
    const panelAddress = document.getElementById('panelAddress');
    const panelCoords = document.getElementById('panelCoords');
    const panelManDistance = document.getElementById('panelManDistance');
    const panelLandmarks = document.getElementById('panelLandmarks');
    const panelNearestPorto = document.getElementById('panelNearestPorto');
    const connectionStatus = document.getElementById('connectionStatus');
    const connectionDot = document.getElementById('connectionDot');
    const simModeIndicator = document.getElementById('simModeIndicator');
    
    if (panelZone) {
      panelZone.textContent = data.zone ? data.zone.toString().replace('_', ' ').toUpperCase() : 'UNKNOWN';
    }
    
    if (panelAddress) {
      panelAddress.textContent = data.address || 'Unknown Location';
    }
    
    if (panelCoords) {
      panelCoords.textContent = data.lat && data.lng ? 
        `${data.lat.toFixed(6)}, ${data.lng.toFixed(6)}` : 'No Signal';
    }
    
    if (panelManDistance) {
      panelManDistance.textContent = data.distance_from_man || 'Unknown';
    }
    
    // Update landmarks list
    if (panelLandmarks) {
      if (data.landmarks && data.landmarks.length > 0) {
        panelLandmarks.innerHTML = '';
        data.landmarks.slice(0, 5).forEach(landmark => {
          const landmarkEl = document.createElement('div');
          landmarkEl.className = 'landmark-item';
          landmarkEl.innerHTML = `
            <span class="landmark-name">${landmark.name}</span>
            <span class="landmark-distance">${Math.round(landmark.distance_meters || 0)}m</span>
          `;
          panelLandmarks.appendChild(landmarkEl);
        });
      } else {
        panelLandmarks.innerHTML = '<div class="no-data">No landmarks nearby</div>';
      }
    }
    
    // Update nearest porto
    if (panelNearestPorto) {
      if (data.nearest_porto) {
        panelNearestPorto.textContent = `${data.nearest_porto.name} (${Math.round(data.nearest_porto.distance_meters || 0)}m)`;
      } else {
        panelNearestPorto.textContent = 'Not available';
      }
    }
    
    // Update connection status
    if (connectionStatus && connectionDot) {
      const now = new Date();
      connectionStatus.textContent = `Online - ${now.toLocaleTimeString()}`;
      connectionDot.className = 'indicator-dot';
      
      // Show simulation mode
      if (simModeIndicator) {
        if (data.source === 'simulation') {
          simModeIndicator.textContent = 'SIMULATION MODE ACTIVE';
        } else if (data.source === 'random_landmark') {
          simModeIndicator.textContent = 'DEMO MODE ACTIVE';
        } else {
          simModeIndicator.textContent = '';
        }
      }
    }
  },
  
  // Update information panel for offline state
  updateInformationPanelOffline: function() {
    const connectionStatus = document.getElementById('connectionStatus');
    const connectionDot = document.getElementById('connectionDot');
    
    if (connectionStatus && connectionDot) {
      connectionStatus.textContent = 'Connection Lost - Retrying...';
      connectionDot.className = 'indicator-dot offline';
    }
  },
  
  // Load route history
  loadRouteHistory: async function() {
    try {
      const response = await fetch(window.APP_CONFIG.api.historyEndpoint);
      const data = await response.json();
      
      if (data.history && data.history.length > 0) {
        if (GPSMap.Markers) {
          GPSMap.Markers.routeHistory = data.history.map(point => ({
            lat: point.lat,
            lng: point.lng,
            timestamp: point.timestamp,
            address: point.address
          }));
          
          console.log(`Loaded ${GPSMap.Markers.routeHistory.length} route points`);
        } else {
          console.warn('GPSMap.Markers not available for route history');
        }
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
      
      // Zone boundaries are handled by the backend LocationContextService
      // No need to fetch them separately in the frontend
      console.log('Zone calculations handled by backend LocationContextService');
      
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
      } else if (GPSMap.MapSetup.map) {
        // Use map center
        const center = GPSMap.MapSetup.map.getCenter();
        lat = center.lat;
        lng = center.lng;
      } else {
        // Use default Black Rock City coordinates
        lat = 40.78696345;
        lng = -119.2030071;
      }
      
      // Validate coordinates
      if (!lat || !lng || isNaN(lat) || isNaN(lng)) {
        console.error('Invalid coordinates for toilet loading:', { lat, lng });
        return;
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
          // Validate toilet coordinates
          if (toilet.lat && toilet.lng && !isNaN(toilet.lat) && !isNaN(toilet.lng)) {
            L.marker([toilet.lat, toilet.lng], {
              icon: L.divIcon({
                className: 'toilet-marker',
                html: '🚽',
                iconSize: [20, 20]
              })
            }).addTo(GPSMap.MapSetup.layers.toilets)
              .bindPopup(toilet.name || 'Portable Toilet');
          } else {
            console.warn('Invalid toilet coordinates:', toilet);
          }
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
      
      // Skip if server error
      if (!response.ok) {
        console.log('Home location endpoint returned error:', response.status);
        return;
      }
      
      // Try to parse as JSON, but catch any errors
      let homeData;
      try {
        homeData = await response.json();
      } catch (parseError) {
        console.log('Home location endpoint returned non-JSON response');
        return;
      }
      
      if (homeData && homeData.lat && homeData.lng) {
        if (GPSMap.Markers && typeof GPSMap.Markers.addHomeMarker === 'function') {
          GPSMap.Markers.addHomeMarker(homeData.lat, homeData.lng, homeData.address);
          console.log('✅ Home location loaded successfully');
        } else {
          console.warn('GPSMap.Markers not available for home marker');
        }
      }
    } catch (error) {
      console.log('Home location not available:', error.message);
    }
  }
};