#!/bin/bash
# Check GitLab readiness without requiring SSH

echo "🔍 Checking GitLab Startup Progress"
echo "=================================="
echo "Time: $(date)"
echo ""

check_count=0
max_checks=20

while [ $check_count -lt $max_checks ]; do
    check_count=$((check_count + 1))
    
    echo -n "[$check_count/$max_checks] Testing GitLab response... "
    
    # Check GitLab response
    response=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:18221/gitlab/ 2>/dev/null)
    
    case $response in
        "200"|"302"|"401")
            echo "✅ SUCCESS! GitLab is ready (HTTP $response)"
            echo ""
            echo "🎉 GitLab is now accessible at: https://localhost:18221/gitlab/"
            echo "🔑 Default credentials: root / admin123456"
            echo ""
            echo "🧪 You can now test the GitLab-Mattermost integration:"
            echo "   1. GitLab: https://localhost:18221/gitlab/"
            echo "   2. Mattermost: https://localhost:18231/mattermost/"
            echo ""
            exit 0
            ;;
        "502")
            echo "⏳ Still starting (Bad Gateway - backend not ready)"
            ;;
        "500")
            echo "⚠️  Internal Server Error (may indicate configuration issue)"
            ;;
        "000"|"")
            echo "❌ No response (nginx may not be started yet)"
            ;;
        *)
            echo "❓ Unexpected response: HTTP $response"
            ;;
    esac
    
    if [ $check_count -lt $max_checks ]; then
        echo "   Waiting 30 seconds before next check..."
        sleep 30
    fi
done

echo ""
echo "⚠️  GitLab startup taking longer than expected (${max_checks} checks)"
echo ""
echo "💡 This can happen on first boot. You can:"
echo "   1. Continue waiting - GitLab can take up to 15 minutes on first boot"
echo "   2. Check manually: curl -k https://localhost:18221/gitlab/"
echo "   3. Check VM resources: the VM may need more memory"
echo ""
echo "🔧 If issues persist, try:"
echo "   ./cli/rave vm stop local-dev"
echo "   ./cli/rave vm start local-dev"