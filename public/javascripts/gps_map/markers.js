// GPS Map Marker Management
window.GPSMap = window.GPSMap || {};

GPSMap.Markers = {
  cubeMarker: null,
  homeMarker: null,
  routePolyline: null,
  routeHistory: [],
  routeMarkers: [],
  
  // Create or update cube marker
  updateCubeMarker: function(lat, lng, locationData) {
    // Remove existing marker
    if (this.cubeMarker) {
      GPSMap.MapSetup.map.removeLayer(this.cubeMarker);
    }
    
    // Create detailed popup content using same data as top info bar
    let popupContent = '🎲 Glitch Cube Location<br>';
    
    if (typeof locationData === 'object' && locationData !== null) {
      // Prioritize street address over landmark name (same logic as updateInfoPanels)
      let address = 'Black Rock City';
      if (locationData.address) {
        address = locationData.address;
        // Add landmark context if available
        if (locationData.landmark_name && locationData.landmark_name !== locationData.address) {
          address += ` (Near ${locationData.landmark_name})`;
        }
      } else if (locationData.landmark_name) {
        address = locationData.landmark_name;
      }
      
      const section = locationData.section || '';
      const distance = locationData.distance_from_man || '';
      
      popupContent += address;
      if (section) {
        popupContent += `<br><strong>${section}</strong>`;
      }
      if (distance) {
        popupContent += `<br>${distance}`;
      }
    } else {
      // Fallback if passed as string (backwards compatibility)
      popupContent += (locationData || 'Black Rock City');
    }
    
    // Create new marker
    const cubeIcon = GPSMap.Icons.createCustomIcon('cube', 36);
    this.cubeMarker = L.marker([lat, lng], { icon: cubeIcon })
      .addTo(GPSMap.MapSetup.map)
      .bindPopup(popupContent);
    
    return this.cubeMarker;
  },
  
  // Add home marker
  addHomeMarker: function(lat, lng, address) {
    if (this.homeMarker) {
      GPSMap.MapSetup.map.removeLayer(this.homeMarker);
    }
    
    const homeIcon = GPSMap.Icons.createCustomIcon('home', 28);
    this.homeMarker = L.marker([lat, lng], { icon: homeIcon })
      .addTo(GPSMap.MapSetup.map)
      .bindPopup(`🏠 HOME<br>${address}`);
    
    return this.homeMarker;
  },
  
  // Add position to route history
  addToRouteHistory: function(lat, lng, timestamp, address) {
    // Only add if position has changed
    if (this.routeHistory.length === 0 || 
        (Math.abs(this.routeHistory[this.routeHistory.length - 1].lat - lat) > 0.00001 ||
         Math.abs(this.routeHistory[this.routeHistory.length - 1].lng - lng) > 0.00001)) {
      
      this.routeHistory.push({
        lat: lat,
        lng: lng,
        timestamp: timestamp,
        address: address
      });
      
      // Keep only last 200 points
      if (this.routeHistory.length > 200) {
        this.routeHistory = this.routeHistory.slice(-200);
      }
      
      // Auto-update route display if it's shown
      if (this.routePolyline) {
        this.toggleRouteHistory(); // Hide
        this.toggleRouteHistory(); // Show updated
      }
    }
  },
  
  // Toggle route history display
  toggleRouteHistory: function() {
    if (this.routePolyline) {
      // Remove existing route
      GPSMap.MapSetup.map.removeLayer(this.routePolyline);
      this.routePolyline = null;
      // Remove route markers
      this.routeMarkers.forEach(marker => GPSMap.MapSetup.map.removeLayer(marker));
      this.routeMarkers = [];
      return false;
    } else if (this.routeHistory.length > 0) {
      const routeCoords = this.routeHistory.map(point => [point.lat, point.lng]);
      
      // Add gradient polyline for the route
      this.routePolyline = L.polyline(routeCoords, {
        color: '#00ff00',
        weight: 3,
        opacity: 0.7,
        smoothFactor: 1.0,
        lineJoin: 'round'
      }).addTo(GPSMap.MapSetup.map);
      
      // Add direction arrows along the route
      if (this.routeHistory.length > 1) {
        for (let i = 0; i < this.routeHistory.length - 1; i += 5) { // Every 5th point
          const point = this.routeHistory[i];
          const nextPoint = this.routeHistory[Math.min(i + 1, this.routeHistory.length - 1)];
          
          // Calculate bearing for arrow direction
          const bearing = GPSMap.Utils.calculateBearing(
            point.lat, point.lng,
            nextPoint.lat, nextPoint.lng
          );
          
          // Add small arrow marker
          const arrowMarker = L.marker([point.lat, point.lng], {
            icon: L.divIcon({
              html: `<div style="transform: rotate(${bearing}deg); color: #00ff00; font-size: 12px;">→</div>`,
              iconSize: [12, 12],
              className: 'route-arrow'
            })
          }).addTo(GPSMap.MapSetup.map);
          this.routeMarkers.push(arrowMarker);
        }
      }
      
      // Add start and end markers
      if (this.routeHistory.length > 0) {
        const startPoint = this.routeHistory[0];
        const endPoint = this.routeHistory[this.routeHistory.length - 1];
        
        const startMarker = L.circleMarker([startPoint.lat, startPoint.lng], {
          radius: 6,
          color: '#00ff00',
          fillColor: '#00ff00',
          fillOpacity: 0.8
        }).bindPopup(`<strong>Route Start</strong><br>${startPoint.address || 'Location'}<br>${new Date(startPoint.timestamp).toLocaleString()}`).addTo(GPSMap.MapSetup.map);
        this.routeMarkers.push(startMarker);
        
        const endMarker = L.circleMarker([endPoint.lat, endPoint.lng], {
          radius: 6,
          color: '#ff0000',
          fillColor: '#ff0000',
          fillOpacity: 0.8
        }).bindPopup(`<strong>Route End</strong><br>${endPoint.address || 'Location'}<br>${new Date(endPoint.timestamp).toLocaleString()}`).addTo(GPSMap.MapSetup.map);
        this.routeMarkers.push(endMarker);
      }
      return true;
    }
    return false;
  },
  
  // Center map on cube
  centerOnCube: function() {
    if (this.cubeMarker) {
      GPSMap.MapSetup.map.setView(this.cubeMarker.getLatLng(), 15);
    }
  }
};