#!/bin/bash
# Monitor VM boot progress

echo "🔍 Monitoring VM Boot Progress"
echo "=============================="

for i in {1..20}; do
    echo -n "[$i/20] "
    
    # Test SSH
    if timeout 3 sshpass -p 'debug123' ssh -o "StrictHostKeyChecking=no" -o "ConnectTimeout=2" root@localhost -p 2224 "echo 'SSH ready'" 2>/dev/null; then
        echo "✅ SSH is ready!"
        
        # Check services
        echo "📊 Checking key services:"
        sshpass -p 'debug123' ssh -o "StrictHostKeyChecking=no" root@localhost -p 2224 "
            echo '  PostgreSQL:' \$(systemctl is-active postgresql.service)
            echo '  Redis:     ' \$(systemctl is-active redis-main.service)
            echo '  GitLab:    ' \$(systemctl is-active gitlab.service)
            echo '  nginx:     ' \$(systemctl is-active nginx.service)
        " 2>/dev/null
        
        # Test GitLab response
        response=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:18221/gitlab/ 2>/dev/null)
        echo "🌐 GitLab HTTP Response: $response"
        
        if [ "$response" = "200" ] || [ "$response" = "302" ]; then
            echo "🎉 GitLab is ready!"
            exit 0
        fi
        
        break
    else
        echo "⏳ SSH not ready yet..."
    fi
    
    sleep 15
done

echo "⚠️  Boot monitoring complete. GitLab may still be initializing."
echo "💡 Try accessing GitLab at: https://localhost:18221/gitlab/"