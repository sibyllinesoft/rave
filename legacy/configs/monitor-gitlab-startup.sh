#!/bin/bash

echo "🔄 Monitoring GitLab startup..."
echo "This may take several minutes for GitLab to complete database migrations."
echo

max_attempts=30  # 15 minutes maximum
attempt=1

while [ $attempt -le $max_attempts ]; do
    echo "📊 Attempt $attempt/$max_attempts ($(date))"
    
    # Check container status
    gitlab_status=$(snap run docker ps --filter "name=gitlab-complete-gitlab-1" --format "{{.Status}}" 2>/dev/null || echo "Not found")
    echo "📦 GitLab container: $gitlab_status"
    
    # Test GitLab health endpoint
    echo "🏥 Testing GitLab health endpoint..."
    if curl -s -f http://localhost:8181/-/health >/dev/null 2>&1; then
        echo "✅ GitLab health endpoint responding!"
        break
    else
        echo "❌ GitLab not ready yet"
    fi
    
    # Test nginx proxy
    echo "🌐 Testing nginx proxy..."
    nginx_response=$(curl -s -I http://localhost:8080 2>&1 | head -n 1 || echo "Connection failed")
    echo "🔄 Nginx response: $nginx_response"
    
    if [ $attempt -eq $max_attempts ]; then
        echo "⏰ Maximum wait time reached. GitLab may still be starting up."
        echo "💡 You can continue monitoring with: snap run docker logs gitlab-complete-gitlab-1 -f"
        exit 1
    fi
    
    echo "⏱️  Waiting 30 seconds before next check..."
    echo "----------------------------------------"
    sleep 30
    attempt=$((attempt + 1))
done

echo
echo "🎉 SUCCESS! GitLab appears to be ready!"
echo "📍 GitLab should now be accessible at: http://localhost:8080"
echo "🔑 Default login: root / ComplexPassword123!"
echo
echo "🧪 Final verification..."
curl -I http://localhost:8080