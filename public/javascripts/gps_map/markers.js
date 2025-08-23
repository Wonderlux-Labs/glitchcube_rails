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
    // If marker exists, animate to new position instead of recreating
    if (this.cubeMarker) {
      this.animateCubeTo(lat, lng, locationData);
      return this.cubeMarker;
    }
    

    let popupContent = '🎲 Glitch Cube Location<br>';
    
    if (typeof locationData === 'object' && locationData !== null) {
      // Get nearest landmark from landmarks array
      let nearestLandmark = null;
      if (locationData.landmarks && locationData.landmarks.length > 0) {
        nearestLandmark = locationData.landmarks[0];
      }
      
      // Show landmark name if very close, otherwise show street address
      let address = 'Black Rock City';
      if (nearestLandmark && nearestLandmark.distance_meters < 5) {
        address = nearestLandmark.name;
        if (locationData.address && locationData.address !== nearestLandmark.name) {
          address += ` (${locationData.address})`;
        }
      } else if (locationData.address) {
        address = locationData.address;
        if (nearestLandmark && nearestLandmark.distance_meters < 50) {
          address += ` (Near ${nearestLandmark.name})`;
        }
      } else if (nearestLandmark) {
        address = nearestLandmark.name;
      }
      
      const zone = locationData.zone ? locationData.zone.toString().replace('_', ' ').toUpperCase() : '';
      const distance = locationData.distance_from_man || '';
      
      popupContent += address;
      if (zone) {
        popupContent += `<br><strong>${zone}</strong>`;
      }
      if (distance) {
        popupContent += `<br>Distance to Man: ${distance}`;
      }
      if (nearestLandmark) {
        const landmarkDistance = Math.round(nearestLandmark.distance_meters || 0);
        popupContent += `<br>Nearest: ${nearestLandmark.name} (${landmarkDistance}m)`;
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
  },
  
  // Animate cube marker to new position
  animateCubeTo: function(lat, lng, locationData) {
    if (!this.cubeMarker) return;
    
    const currentLatLng = this.cubeMarker.getLatLng();
    const newLatLng = L.latLng(lat, lng);
    
    // Skip animation if distance is too small (less than ~1 meter)
    const distance = currentLatLng.distanceTo(newLatLng);
    if (distance < 1) {
      this.updateCubePopup(locationData);
      return;
    }
    
    // Smooth animation to new position
    const duration = Math.min(2000, Math.max(500, distance * 10)); // 500ms to 2s based on distance
    
    // Add CSS class for smooth transition
    const markerElement = this.cubeMarker._icon;
    if (markerElement) {
      markerElement.style.transition = `transform ${duration}ms ease-out`;
    }
    
    // Update position with animation
    this.cubeMarker.setLatLng(newLatLng);
    
    // Update popup content
    this.updateCubePopup(locationData);
    
    // Remove transition after animation completes
    setTimeout(() => {
      if (markerElement) {
        markerElement.style.transition = '';
      }
    }, duration);
  },
  
  // Update cube popup content
  updateCubePopup: function(locationData) {
    if (!this.cubeMarker) return;
    
    let popupContent = '🎲 Glitch Cube Location<br>';
    
    if (typeof locationData === 'object' && locationData !== null) {
      // Get nearest landmark from landmarks array
      let nearestLandmark = null;
      if (locationData.landmarks && locationData.landmarks.length > 0) {
        nearestLandmark = locationData.landmarks[0];
      }
      
      // Show landmark name if very close, otherwise show street address
      let address = 'Black Rock City';
      if (nearestLandmark && nearestLandmark.distance_meters < 5) {
        address = nearestLandmark.name;
        if (locationData.address && locationData.address !== nearestLandmark.name) {
          address += ` (${locationData.address})`;
        }
      } else if (locationData.address) {
        address = locationData.address;
        if (nearestLandmark && nearestLandmark.distance_meters < 50) {
          address += ` (Near ${nearestLandmark.name})`;
        }
      } else if (nearestLandmark) {
        address = nearestLandmark.name;
      }
      
      const zone = locationData.zone ? locationData.zone.toString().replace('_', ' ').toUpperCase() : '';
      const distance = locationData.distance_from_man || '';
      
      popupContent += address;
      if (zone) {
        popupContent += `<br><strong>${zone}</strong>`;
      }
      if (distance) {
        popupContent += `<br>Distance to Man: ${distance}`;
      }
      if (nearestLandmark) {
        const landmarkDistance = Math.round(nearestLandmark.distance_meters || 0);
        popupContent += `<br>Nearest: ${nearestLandmark.name} (${landmarkDistance}m)`;
      }
    } else {
      // Fallback if passed as string (backwards compatibility)
      popupContent += (locationData || 'Black Rock City');
    }
    
    this.cubeMarker.setPopupContent(popupContent);
  }
};