#!/usr/bin/env python3
"""
Claude Code Context Monitor
Real-time context usage monitoring with visual indicators and session analytics
"""

import json
import sys
import os
import re
import subprocess

def shorten_model_name(model_name, model_id):
    """Shorten model name to be more compact.

    Examples:
        'Claude Sonnet 4.5' + 'xxx[1m]' -> 'Sonnet 4.5 [1M]'
        'Claude Opus 3.5' + 'xxx[200k]' -> 'Opus 3.5 [200K]'
        'global.anthropic.claude-sonnet-4-5-xxx[1m]' -> 'Sonnet 4.5 [1M]'
    """
    # Extract model type (Sonnet, Opus, Haiku)
    model_type = None
    for t in ['Sonnet', 'Opus', 'Haiku']:
        if t.lower() in model_name.lower() or t.lower() in model_id.lower():
            model_type = t
            break

    if not model_type:
        # If can't detect, use display name but limit length
        return model_name[:20] if len(model_name) > 20 else model_name

    # Extract version number (e.g., "4.5", "3.5")
    # Try model_name first, then model_id
    version_match = re.search(r'(\d+)[.-](\d+)', model_name)
    if not version_match:
        version_match = re.search(r'(\d+)-(\d+)', model_id)

    version = f"{version_match.group(1)}.{version_match.group(2)}" if version_match else ""

    # Extract context window from model_id
    context_suffix = ""
    context_match = re.search(r'\[(\d+)(m|k)\]', model_id.lower())
    if context_match:
        num = context_match.group(1)
        unit = context_match.group(2).upper()
        context_suffix = f" [{num}{unit}]"

    # Build shortened name
    result = f"{model_type}"
    if version:
        result += f" {version}"
    result += context_suffix

    return result

def get_keyboard_layout():
    """Get current keyboard layout on macOS.

    Returns:
        str: Emoji indicator only for non-English layouts (empty string for EN).
             Non-English: '😱' (screaming face) - "ааа, не та раскладка!"
    """
    try:
        # Method: Read keyboard layout from system preferences
        result = subprocess.run(
            ['defaults', 'read', 'com.apple.HIToolbox', 'AppleCurrentKeyboardLayoutInputSourceID'],
            capture_output=True,
            text=True,
            timeout=0.5
        )

        if result.returncode == 0:
            layout = result.stdout.strip().lower()
            # Check for non-English layouts
            # Examples: com.apple.keylayout.Russian, com.apple.keylayout.RussianWin, com.apple.keylayout.ABC

            # Russian/Cyrillic layouts - check FIRST (before US check!)
            if 'russian' in layout or '.ru' in layout or 'cyrillic' in layout:
                return "😱"  # Screaming face - "ааа, русская!"

            # English layouts - no indicator
            if '.abc' in layout or '.us' in layout or 'english' in layout or layout.endswith('abc'):
                return ""  # English - no indicator to save space

            # Any other keyboard layout (non-English)
            if 'keylayout' in layout:
                return "😱"  # Other non-English layout

            return ""

    except Exception:
        pass

    # Default to empty (English is most common)
    return ""

def get_context_window_size(model_id):
    """Extract context window size from model ID.

    Looks for [XM] or [Xk] suffix in model ID to determine context window.
    Examples:
        - model[1m] = 1,000,000 tokens
        - model[200k] = 200,000 tokens
        - Default = 200,000 tokens
    """
    if not model_id:
        return 200000

    # Look for [1m], [200k], etc. in model ID
    match = re.search(r'\[(\d+)(m|k)\]', model_id.lower())
    if match:
        number = int(match.group(1))
        unit = match.group(2)

        if unit == 'm':
            return number * 1000000
        elif unit == 'k':
            return number * 1000

    # Default to 200k for older models
    return 200000

def parse_context_from_transcript(transcript_path, context_window=200000):
    """Parse context usage from transcript file."""
    if not transcript_path or not os.path.exists(transcript_path):
        return None

    try:
        with open(transcript_path, 'r', encoding='utf-8', errors='replace') as f:
            lines = f.readlines()

        # Check last 15 lines for context information
        recent_lines = lines[-15:] if len(lines) > 15 else lines

        for line in reversed(recent_lines):
            try:
                data = json.loads(line.strip())

                # Method 1: Parse usage tokens from assistant messages
                if data.get('type') == 'assistant':
                    message = data.get('message', {})
                    usage = message.get('usage', {})

                    if usage:
                        input_tokens = usage.get('input_tokens', 0)
                        cache_read = usage.get('cache_read_input_tokens', 0)
                        cache_creation = usage.get('cache_creation_input_tokens', 0)

                        # Calculate context usage based on model's actual context window
                        total_tokens = input_tokens + cache_read + cache_creation
                        if total_tokens > 0:
                            percent_used = min(100, (total_tokens / context_window) * 100)
                            return {
                                'percent': percent_used,
                                'tokens': total_tokens,
                                'context_window': context_window,
                                'method': 'usage'
                            }
                
                # Method 2: Parse system context warnings
                elif data.get('type') == 'system_message':
                    content = data.get('content', '')
                    
                    # "Context left until auto-compact: X%"
                    match = re.search(r'Context left until auto-compact: (\d+)%', content)
                    if match:
                        percent_left = int(match.group(1))
                        return {
                            'percent': 100 - percent_left,
                            'warning': 'auto-compact',
                            'method': 'system'
                        }
                    
                    # "Context low (X% remaining)"
                    match = re.search(r'Context low \((\d+)% remaining\)', content)
                    if match:
                        percent_left = int(match.group(1))
                        return {
                            'percent': 100 - percent_left,
                            'warning': 'low',
                            'method': 'system'
                        }
            
            except (json.JSONDecodeError, KeyError, ValueError):
                continue
        
        return None
        
    except (FileNotFoundError, PermissionError):
        return None

def get_context_display(context_info):
    """Generate context display with visual indicators."""
    if not context_info:
        return "🔵 ???"

    percent = context_info.get('percent', 0)
    tokens = context_info.get('tokens', 0)
    context_window = context_info.get('context_window', 200000)
    warning = context_info.get('warning')

    # Color and icon based on usage level
    if percent >= 95:
        icon, color = "🚨", "\033[31;1m"  # Blinking red
        alert = "CRIT"
    elif percent >= 90:
        icon, color = "🔴", "\033[31m"    # Red
        alert = "HIGH"
    elif percent >= 75:
        icon, color = "🟠", "\033[91m"   # Light red
        alert = ""
    elif percent >= 50:
        icon, color = "🟡", "\033[33m"   # Yellow
        alert = ""
    else:
        icon, color = "🟢", "\033[32m"   # Green
        alert = ""

    # Create progress bar
    segments = 8
    filled = int((percent / 100) * segments)
    bar = "█" * filled + "▁" * (segments - filled)

    # Special warnings
    if warning == 'auto-compact':
        alert = "AUTO-COMPACT!"
    elif warning == 'low':
        alert = "LOW!"

    # Premium pricing warning (>200K tokens = 2x cost)
    premium_pricing = ""
    if context_window >= 1000000 and tokens > 200000:
        premium_pricing = " \033[33m💸2x\033[0m"  # Indicator for premium pricing

    reset = "\033[0m"
    alert_str = f" {alert}" if alert else ""

    return f"{icon}{color}{bar}{reset} {percent:.0f}%{alert_str}{premium_pricing}"

def get_directory_display(workspace_data):
    """Get directory display name."""
    current_dir = workspace_data.get('current_dir', '')
    project_dir = workspace_data.get('project_dir', '')
    
    if current_dir and project_dir:
        if current_dir.startswith(project_dir):
            rel_path = current_dir[len(project_dir):].lstrip('/')
            return rel_path or os.path.basename(project_dir)
        else:
            return os.path.basename(current_dir)
    elif project_dir:
        return os.path.basename(project_dir)
    elif current_dir:
        return os.path.basename(current_dir)
    else:
        return "unknown"

def get_session_metrics(cost_data):
    """Get session metrics display."""
    if not cost_data:
        return ""
    
    metrics = []
    
    # Cost
    cost_usd = cost_data.get('total_cost_usd', 0)
    if cost_usd > 0:
        if cost_usd >= 0.10:
            cost_color = "\033[31m"  # Red for expensive
        elif cost_usd >= 0.05:
            cost_color = "\033[33m"  # Yellow for moderate
        else:
            cost_color = "\033[32m"  # Green for cheap
        
        cost_str = f"{cost_usd*100:.0f}¢" if cost_usd < 0.01 else f"${cost_usd:.3f}"
        metrics.append(f"{cost_color}💰 {cost_str}\033[0m")
    
    # Duration
    duration_ms = cost_data.get('total_duration_ms', 0)
    if duration_ms > 0:
        minutes = duration_ms / 60000
        if minutes >= 30:
            duration_color = "\033[33m"  # Yellow for long sessions
        else:
            duration_color = "\033[32m"  # Green
        
        if minutes < 1:
            duration_str = f"{duration_ms//1000}s"
        else:
            duration_str = f"{minutes:.0f}m"
        
        metrics.append(f"{duration_color}⏱ {duration_str}\033[0m")
    
    # Lines changed
    lines_added = cost_data.get('total_lines_added', 0)
    lines_removed = cost_data.get('total_lines_removed', 0)
    if lines_added > 0 or lines_removed > 0:
        net_lines = lines_added - lines_removed
        
        if net_lines > 0:
            lines_color = "\033[32m"  # Green for additions
        elif net_lines < 0:
            lines_color = "\033[31m"  # Red for deletions
        else:
            lines_color = "\033[33m"  # Yellow for neutral
        
        sign = "+" if net_lines >= 0 else ""
        metrics.append(f"{lines_color}📝 {sign}{net_lines}\033[0m")
    
    return f" \033[90m|\033[0m {' '.join(metrics)}" if metrics else ""

def main():
    try:
        # Read JSON input from Claude Code
        data = json.load(sys.stdin)

        # Extract information
        model_data = data.get('model', {})
        model_name = model_data.get('display_name', 'Claude')
        model_id = model_data.get('id', '')
        workspace = data.get('workspace', {})
        transcript_path = data.get('transcript_path', '')
        cost_data = data.get('cost', {})

        # Shorten model name for compact display
        model_name_short = shorten_model_name(model_name, model_id)

        # Detect context window size from model ID
        context_window = get_context_window_size(model_id)

        # Parse context usage with dynamic context window
        context_info = parse_context_from_transcript(transcript_path, context_window)

        # Build status components
        context_display = get_context_display(context_info)
        directory = get_directory_display(workspace)
        session_metrics = get_session_metrics(cost_data)
        keyboard_layout = get_keyboard_layout()
        
        # Model display with context-aware coloring
        if context_info:
            percent = context_info.get('percent', 0)
            if percent >= 90:
                model_color = "\033[31m"  # Red
            elif percent >= 75:
                model_color = "\033[33m"  # Yellow
            else:
                model_color = "\033[32m"  # Green

            model_display = f"{model_color}[{model_name_short}]\033[0m"
        else:
            model_display = f"\033[94m[{model_name_short}]\033[0m"

        # Combine all components with keyboard layout indicator (only if non-English)
        layout_indicator = f" {keyboard_layout}" if keyboard_layout else ""
        status_line = f"{model_display} \033[93m📁 {directory}\033[0m 🧠 {context_display}{session_metrics}{layout_indicator}"
        
        print(status_line)
        
    except Exception as e:
        # Fallback display on any error
        print(f"\033[94m[Claude]\033[0m \033[93m📁 {os.path.basename(os.getcwd())}\033[0m 🧠 \033[31m[Error: {str(e)[:20]}]\033[0m")

if __name__ == "__main__":
    main()