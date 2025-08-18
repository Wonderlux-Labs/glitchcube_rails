// GPS Map Landmark Management
window.GPSMap = window.GPSMap || {};

GPSMap.Landmarks = {
  landmarks: [],
  
  // Load landmarks and add to map
  loadLandmarks: function(landmarkData) {
    this.landmarks = landmarkData.map(landmark => ({
      name: landmark.name,
      lat: landmark.lat,
      lng: landmark.lng,
      type: landmark.type,
      priority: GPSMap.Utils.getPriorityForType(landmark.type),
      description: landmark.description || landmark.name,
      marker: null
    }));
    
    this.addLandmarksToMap();
  },
  
  // Add landmarks to map
  addLandmarksToMap: function() {
    this.landmarks.forEach(landmark => {
      // Use custom icons for special landmarks, emoji for others
      let landmarkIcon;
      if (landmark.type === 'center') {
        landmarkIcon = GPSMap.Icons.createCustomIcon('man', 24);
      } else if (landmark.type === 'sacred') {
        landmarkIcon = GPSMap.Icons.createCustomIcon('temple', 24);
      } else {
        landmarkIcon = GPSMap.Icons.createLandmarkIcon(landmark.type, 24);
      }
      
      landmark.marker = L.marker([landmark.lat, landmark.lng], {
        icon: landmarkIcon
      });
      
      landmark.marker.bindPopup(`
        <div style="text-align: center; font-family: 'SF Mono', monospace;">
          <strong style="color: #ff8c42; font-size: 16px;">${landmark.name}</strong><br>
          <span style="color: #666; font-size: 12px;">${landmark.description}</span>
        </div>
      `);
    });
    
    // Add city boundary circle
    const centerCamp = this.landmarks.find(l => l.name === 'Center Camp');
    const centerLat = centerCamp ? centerCamp.lat : window.APP_CONFIG.goldenSpike.lat;
    const centerLng = centerCamp ? centerCamp.lng : window.APP_CONFIG.goldenSpike.lng;
    
    L.circle([centerLat, centerLng], {
      color: '#ff6b35',
      fillColor: 'transparent',
      fillOpacity: 0.05,
      radius: GPSMap.Utils.metersToLeafletRadius(2012, centerLat), // 1.25 miles
      weight: 2,
      dashArray: '5, 5'
    }).addTo(GPSMap.MapSetup.layers.landmarks);
  },
  
  // Update landmark visibility based on toggles
  updateLandmarkVisibility: function(showPortos, showMedical, showLandmarks) {
    this.landmarks.forEach(landmark => {
      if (!landmark.marker) return;
      
      let shouldShow = false;
      
      switch(landmark.type) {
        case 'toilet':
          shouldShow = showPortos;
          break;
        case 'medical':
          shouldShow = showMedical;
          break;
        case 'art':
        case 'poi': 
        case 'center':
        case 'sacred':
        case 'gathering':
        case 'service':
        case 'transport':
          shouldShow = showLandmarks;
          break;
        default:
          shouldShow = showLandmarks;
      }
      
      if (shouldShow && !GPSMap.MapSetup.map.hasLayer(landmark.marker)) {
        landmark.marker.addTo(GPSMap.MapSetup.map);
      } else if (!shouldShow && GPSMap.MapSetup.map.hasLayer(landmark.marker)) {
        GPSMap.MapSetup.map.removeLayer(landmark.marker);
      }
    });
  },
  
  // Update landmark proximity highlighting
  updateLandmarkProximity: function(cubeLatLng) {
    const zoom = GPSMap.MapSetup.map.getZoom();
    
    this.landmarks.forEach(landmark => {
      if (landmark.marker) {
        const distance = GPSMap.Utils.haversineDistance(
          cubeLatLng.lat, cubeLatLng.lng,
          landmark.lat, landmark.lng
        );
        
        // Highlight landmarks within proximity threshold
        if (distance <= GPSMap.Utils.PROXIMITY_THRESHOLD_METERS) {
          let proximityIcon;
          if (landmark.type === 'center') {
            proximityIcon = GPSMap.Icons.createCustomIcon('man', 28);
          } else if (landmark.type === 'sacred') {
            proximityIcon = GPSMap.Icons.createCustomIcon('temple', 28);
          } else {
            proximityIcon = GPSMap.Icons.createLandmarkIcon(landmark.type, 28);
          }
          proximityIcon.options.className += ' proximity-highlight';
          landmark.marker.setIcon(proximityIcon);
        } else {
          let normalIcon;
          if (landmark.type === 'center') {
            normalIcon = GPSMap.Icons.createCustomIcon('man', 24);
          } else if (landmark.type === 'sacred') {
            normalIcon = GPSMap.Icons.createCustomIcon('temple', 24);
          } else {
            normalIcon = GPSMap.Icons.createLandmarkIcon(landmark.type, 24);
          }
          landmark.marker.setIcon(normalIcon);
        }
      }
    });
  },
  
  // Get nearby landmarks
  getNearbyLandmarks: function(lat, lng) {
    return this.landmarks.filter(landmark => {
      const distance = GPSMap.Utils.haversineDistance(
        lat, lng, landmark.lat, landmark.lng
      );
      return distance <= GPSMap.Utils.PROXIMITY_THRESHOLD_METERS;
    });
  }
};