#!/bin/bash

echo "🔧 Fixing Grafana URLs in IP Manager..."

# Fix Frontend (App.js)
echo ""
echo "📝 Updating frontend/src/App.js..."
cd /home/ubuntu/ipmanager/frontend/src

if grep -q "192.168.0.100:3001" App.js; then
    sed -i 's|http://192.168.0.100:3001|http://localhost:3001|g' App.js
    echo "✓ Frontend URLs updated (192.168.0.100:3001 → localhost:3001)"
else
    echo "✓ Frontend URLs already correct"
fi

# The React dev server will auto-reload

echo ""
echo "✅ All Grafana URLs fixed!"
echo ""
echo "📊 Grafana Dashboard: http://localhost:3001"
echo "🌐 IP Manager: http://localhost:3000"
