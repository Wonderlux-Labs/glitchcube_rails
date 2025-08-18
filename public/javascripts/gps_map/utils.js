// GPS Map Utilities
window.GPSMap = window.GPSMap || {};

GPSMap.Utils = {
  // Constants for accurate meter calculations at Burning Man
  BURNING_MAN_LAT: 40.7831,
  PROXIMITY_THRESHOLD_METERS: 20,
  LANDMARK_VISIBILITY_METERS: 20,

  // Accurate haversine distance calculation in meters
  haversineDistance: function(lat1, lon1, lat2, lon2) {
    const R = 6371000; // Earth's radius in meters
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
        Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
        Math.sin(dLon/2) * Math.sin(dLon/2);
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
  },

  // Convert meters to Leaflet radius (degrees) at Burning Man latitude
  metersToLeafletRadius: function(meters, lat) {
    lat = lat || this.BURNING_MAN_LAT;
    return meters / (111320 * Math.cos(lat * Math.PI / 180));
  },

  // Get meters per pixel at current zoom
  getMetersPerPixel: function(zoom, lat) {
    lat = lat || this.BURNING_MAN_LAT;
    return 156543.03392 * Math.cos(lat * Math.PI / 180) / Math.pow(2, zoom);
  },

  // Calculate bearing between two points
  calculateBearing: function(lat1, lng1, lat2, lng2) {
    const dLon = (lng2 - lng1) * Math.PI / 180;
    const lat1Rad = lat1 * Math.PI / 180;
    const lat2Rad = lat2 * Math.PI / 180;
    
    const y = Math.sin(dLon) * Math.cos(lat2Rad);
    const x = Math.cos(lat1Rad) * Math.sin(lat2Rad) -
              Math.sin(lat1Rad) * Math.cos(lat2Rad) * Math.cos(dLon);
    
    const bearing = Math.atan2(y, x) * 180 / Math.PI;
    return (bearing + 360) % 360;
  },

  // Get priority for landmark type
  getPriorityForType: function(type) {
    switch (type) {
      case 'sacred':
      case 'center':  
      case 'art':
        return 1; // Major landmarks
      case 'medical':
      case 'ranger':
      case 'service':
        return 2; // Emergency/service
      default:
        return 3; // Other landmarks
    }
  },

  // Get color based on landmark type
  getEffectColor: function(type) {
    switch (type) {
      case 'sacred': return '#ffffff';
      case 'center': return '#ff6b35';
      case 'medical': return '#ff0000';
      case 'service': return '#0066ff';
      case 'transport': return '#ffff00';
      default: return '#ff6b35';
    }
  }
};