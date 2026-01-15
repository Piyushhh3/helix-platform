#!/usr/bin/env python3
"""
Quick test script for AI analyzer
Run: python test_ai.py
"""

import os
import sys
from dotenv import load_dotenv

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from classifiers.hybrid_classifier import HybridClassifier

# Load environment
load_dotenv()

def test_ai_analyzer():
    """Test the AI analyzer with a sample alert"""
    
    # Initialize classifier
    classifier = HybridClassifier()
    
    # Sample alert
    alert = {
        "labels": {
            "alertname": "UnknownPerformanceIssue",
            "severity": "warning",
            "service": "order-service",
            "namespace": "helix-dev"
        },
        "annotations": {
            "description": "order-service response time increased by 300% in last 10 minutes",
            "summary": "Unusual performance degradation"
        },
        "startsAt": "2024-01-15T10:30:00Z"
    }
    
    # Sample metrics
    recent_metrics = [
        {"name": "response_time_p95", "value": "1.2s"},
        {"name": "error_rate", "value": "2.3%"},
        {"name": "cpu_usage", "value": "45%"},
        {"name": "memory_usage", "value": "68%"},
    ]
    
    # Sample logs
    pod_logs = """
2024-01-15 10:25:00 INFO Starting request processing
2024-01-15 10:25:05 WARNING Database query slow: 850ms
2024-01-15 10:25:10 ERROR Timeout waiting for product-service
2024-01-15 10:25:15 WARNING Database query slow: 920ms
2024-01-15 10:25:20 ERROR Timeout waiting for product-service
    """
    
    print("=" * 80)
    print("TESTING HYBRID CLASSIFIER")
    print("=" * 80)
    
    # Classify
    action = classifier.classify(
        alert=alert,
        recent_metrics=recent_metrics,
        pod_logs=pod_logs
    )
    
    # Display result
    print("\n📊 CLASSIFICATION RESULT:")
    print(f"  Action Type: {action.action_type}")
    print(f"  Target: {action.target}")
    print(f"  Confidence: {action.confidence:.2f}")
    print(f"  Reason: {action.reason}")
    print(f"  Parameters: {action.parameters}")
    
    # Auto-execute decision
    should_execute = classifier.should_auto_execute(action)
    print(f"\n🤖 Auto-execute: {'✅ YES' if should_execute else '❌ NO (needs approval)'}")
    
    # Statistics
    print("\n📈 STATISTICS:")
    stats = classifier.get_stats()
    for key, value in stats.items():
        print(f"  {key}: {value}")
    
    print("\n" + "=" * 80)

if __name__ == "__main__":
    # Check for API key
    if not os.getenv("GROQ_API_KEY"):
        print("⚠️  WARNING: GROQ_API_KEY not set!")
        print("Get your free API key from: https://console.groq.com")
        print("\nYou can still test rule-based classification.")
        print()
    
    test_ai_analyzer()
