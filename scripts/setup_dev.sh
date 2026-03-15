#!/bin/bash
# Fleetforce Development Environment Setup Script

echo "🐺 Starting Fleetforce Scratch Org Spin-Up!"

# 1. Create the Scratch Org
echo "⏳ Creating Scratch Org (fleetforce-dev)..."
sf org create scratch -f config/project-scratch-def.json -a fleetforce-dev -d -y 30 --wait 20
if [ $? -ne 0 ]; then
    echo "❌ Failed to create Scratch Org."
    exit 1
fi
echo "✅ Scratch Org created."

# 2. Deploy Metadata
echo "⏳ Deploying Phase 1 Metadata (This might take a few minutes)..."
sf project deploy start
if [ $? -ne 0 ]; then
    echo "❌ Deployment Failed. Check errors above."
    exit 1
fi
echo "✅ Metadata deployed successfully."

# 3. Assign Permission Set
echo "⏳ Assigning FleetAdmin Permission Set..."
sf org assign permset -n FleetAdmin
if [ $? -ne 0 ]; then
    echo "❌ Failed to assign Permission Set."
    exit 1
fi
echo "✅ Permission Set assigned."

# 4. Success & Open
echo "🎉 Setup Complete! Opening org in your browser..."
sf org open

echo "Next Step: You can now safely run python3 seeder.py to load dummy data!"
