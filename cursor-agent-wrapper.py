#!/usr/bin/env python3
"""
Wrapper for cursor-agent that simulates -p mode by automating interactive input.
Works with TUI (ncurses-based) applications.

Usage: ./cursor-agent-wrapper.py --model <model> -p "prompts"
       ./cursor-agent-wrapper.py --model <model> -p "prompts" --clean  # Clean output
"""

import argparse
import sys
import os
import time
import re

try:
    import pexpect
except ImportError:
    print("Error: pexpect not installed. Run: pip install pexpect", file=sys.stderr)
    sys.exit(1)


def read_prompt_file(prompt_path):
    """Read prompt from file if path is provided."""
    if os.path.isfile(prompt_path):
        with open(prompt_path, 'r') as f:
            return f.read().strip()
    return prompt_path


def clean_output(text):
    """Extract final agent response from cursor-agent TUI output."""
    
    # Remove ANSI escape sequences
    text = re.sub(r'\x1b\[[0-9;]*[A-Za-z]', '', text)
    text = re.sub(r'\x1b\[[0-9;]*m', '', text)
    
    # Remove other control characters
    text = re.sub(r'\x1b\][^\x07]*\x07', '', text)  # OSC sequences
    text = text.replace('\x0d', '')  # carriage returns
    text = text.replace('\r', '')
    
    # Split into lines
    lines = text.split('\n')
    
    # Track content lines (agent's actual response)
    content_lines = []
    seen_content = set()
    
    for line in lines:
        # Skip empty lines
        stripped = line.strip()
        if not stripped:
            continue
        
        # Skip UI elements
        if any(skip in stripped for skip in [
            'Auto-run', 'shift+tab', '/ commands', '@ files', '! shell',
            'Claude 4.5', 'Claude 3', 'Generating', 'Thinking', 'Running',
            'tokens', 'ctrl+c', 'ctrl+o', 'INSERT', 'Plan, search, build',
            'truncated', 'Add a follow-up'
        ]):
            continue
        
        # Skip box drawing and input lines
        if re.match(r'^[│┌┐└┘├┤┬┴┼─\s→]+', stripped):
            continue
        if stripped.startswith('│') or stripped.startswith('→'):
            continue
            
        # Skip command menu lines
        if re.match(r'^/\w+', stripped):
            continue
            
        # Skip lines that are just special characters
        if re.match(r'^[⬡⬢⬣▶︎■•\s]+$', stripped):
            continue
        
        # Skip shell command timing lines (e.g., "$ pip install ipython 404ms")
        if re.match(r'^\$.*\d+ms$', stripped):
            continue
        
        # Skip incomplete pip output fragments
        if re.match(r'^\(\d+\.\d+\.\d+\)$', stripped):  # e.g., "(5.2.1)"
            continue
       
        # Clean the line - remove leading bullets/markers
        cleaned = re.sub(r'^[⬡⬢⬣▶︎■•\s]+', '', stripped)
        if not cleaned:
            continue
        
        # Deduplicate (TUI often repeats lines as they're being typed)
        if cleaned in seen_content:
            continue
        
        seen_content.add(cleaned)
        content_lines.append(cleaned)
    
    # Find the actual response by looking for the final complete version
    # The TUI shows incremental text, so we want the longest version of each line
    final_lines = []
    i = 0
    while i < len(content_lines):
        line = content_lines[i]
        # Check if next lines are extensions of this one
        j = i + 1
        while j < len(content_lines) and content_lines[j].startswith(line[:min(20, len(line))]):
            line = content_lines[j]
            j += 1
        final_lines.append(line)
        i = j if j > i + 1 else i + 1
    
    return '\n'.join(final_lines)


def run_cursor_agent(model, prompt, extra_args=None, timeout=600, idle_timeout=60, verbose=False, clean=False):
    """
    Run cursor-agent in interactive mode and inject the prompt.
    """
    cmd_parts = ['cursor-agent', '--model', model]
    
    if extra_args:
        cmd_parts.extend(extra_args)
    
    cmd = ' '.join(cmd_parts)
    
    if verbose:
        print(f"[DEBUG] Running: {cmd}", file=sys.stderr)
        print(f"[DEBUG] Prompt length: {len(prompt)} chars", file=sys.stderr)
    
    # Spawn with proper terminal size
    child = pexpect.spawn(cmd, encoding='utf-8', timeout=timeout, dimensions=(50, 120))
    
    # Wait for TUI to fully initialize
    if verbose:
        print("[DEBUG] Waiting for TUI to initialize...", file=sys.stderr)
    time.sleep(3)
    
    # Drain initial output and wait for TUI to be ready
    tui_ready = False
    for _ in range(10):  # Try up to 10 times
        try:
            initial_output = child.read_nonblocking(size=65536, timeout=1)
            # Look for signs the TUI is ready (input field, prompt indicator)
            if '│' in initial_output or '→' in initial_output or 'Auto-run' in initial_output:
                tui_ready = True
                if verbose:
                    print("[DEBUG] TUI ready indicator found", file=sys.stderr)
                break
        except pexpect.TIMEOUT:
            pass
        time.sleep(0.5)
    
    if not tui_ready and verbose:
        print("[DEBUG] Warning: TUI ready indicator not found, proceeding anyway", file=sys.stderr)
    
    # Extra delay to ensure TUI is ready for input
    time.sleep(1)
    
    # Buffer for clean output mode
    output_buffer = []
    
    try:
        # Enable auto-run mode first
        if verbose:
            print("[DEBUG] Enabling auto-run...", file=sys.stderr)
        
        # Send a dummy character and backspace to "wake up" the input field
        # This ensures the TUI is ready to receive the actual command
        child.send(' ')
        time.sleep(0.1)
        child.send('\x7f')  # Backspace (DEL)
        time.sleep(0.2)
        
        # Type the command with a longer delay for the first character
        cmd = '/auto-run on'
        child.send(cmd[0])  # Send '/' first
        time.sleep(0.1)  # Wait a bit longer for the first char
        for char in cmd[1:]:
            child.send(char)
            time.sleep(0.02)
        
        time.sleep(0.5)
        child.send('\r')  # Enter
        time.sleep(1.5)
        
        if verbose:
            print("[DEBUG] Sending prompt...", file=sys.stderr)
        
        # Wake up input field before sending prompt
        child.send(' ')
        time.sleep(0.1)
        child.send('\x7f')  # Backspace
        time.sleep(0.2)
        
        # Send the prompt with longer initial delay
        if len(prompt) > 0:
            child.send(prompt[0])
            time.sleep(0.05)
            for char in prompt[1:]:
                child.send(char)
                time.sleep(0.01)
        
        time.sleep(0.5)
        
        # Submit with Enter
        if verbose:
            print("[DEBUG] Submitting with Enter...", file=sys.stderr)
        child.send('\r')  # Regular Enter
        time.sleep(1.5)
        
        if verbose:
            print("[DEBUG] Monitoring output...", file=sys.stderr)
        
        # Monitor output
        last_output_time = time.time()
        last_busy_indicator_time = None
        work_started = False
        prompt_submitted_time = time.time()
        retry_count = 0
        
        # Busy indicator pattern - "..." typically indicates processing
        busy_pattern = r'\.\.\.'
        
        while True:
            try:
                chunk = child.read_nonblocking(size=4096, timeout=2)
                if chunk:
                    if clean:
                        # Buffer output for cleaning later
                        output_buffer.append(chunk)
                    else:
                        sys.stdout.write(chunk)
                        sys.stdout.flush()
                    last_output_time = time.time()
                    
                    # Check for busy indicator "..."
                    if re.search(busy_pattern, chunk):
                        last_busy_indicator_time = time.time()
                        if verbose and not work_started:
                            print(f"\n[DEBUG] Busy indicator detected!", file=sys.stderr)
                        work_started = True
                            
            except pexpect.TIMEOUT:
                idle_time = time.time() - last_output_time
                elapsed = time.time() - prompt_submitted_time
                
                # Calculate time since last busy indicator
                busy_idle_time = None
                if last_busy_indicator_time:
                    busy_idle_time = time.time() - last_busy_indicator_time
                
                if verbose and idle_time > 3:
                    status = "working" if work_started else "waiting"
                    busy_info = f", busy_idle: {busy_idle_time:.0f}s" if busy_idle_time else ""
                    print(f"\r[DEBUG] {status}, idle: {idle_time:.0f}s{busy_info}, elapsed: {elapsed:.0f}s   ", 
                          file=sys.stderr, end='')
                
                # Task complete if busy indicator stopped (no "..." for a while)
                if last_busy_indicator_time and busy_idle_time and busy_idle_time > 10:
                    if verbose:
                        print(f"\n[DEBUG] Task complete (busy indicator stopped)", file=sys.stderr)
                    break
                
                # Task complete if work started and now idle (fallback)
                if work_started and idle_time > idle_timeout:
                    if verbose:
                        print(f"\n[DEBUG] Task complete (idle timeout)", file=sys.stderr)
                    break
                
                # If no work after a while, try submitting again
                if not work_started and idle_time > 10 and retry_count < 3:
                    retry_count += 1
                    if verbose:
                        print(f"\n[DEBUG] Retry #{retry_count}: pressing Enter...", file=sys.stderr)
                    child.send('\r')
                    time.sleep(0.3)
                    child.send('\n')
                    last_output_time = time.time()
                    
                # Overall timeout
                if elapsed > timeout:
                    if verbose:
                        print(f"\n[DEBUG] Overall timeout", file=sys.stderr)
                    break
                    
            except pexpect.EOF:
                if verbose:
                    print("\n[DEBUG] Process ended", file=sys.stderr)
                break
        
        # Exit gracefully
        if child.isalive():
            if verbose:
                print("\n[DEBUG] Exiting...", file=sys.stderr)
            child.sendcontrol('c')
            time.sleep(0.3)
            child.send('/exit\r')
            try:
                child.expect(pexpect.EOF, timeout=3)
            except:
                child.terminate(force=True)
        
        # Output cleaned result if clean mode is enabled
        if clean and output_buffer:
            raw_output = ''.join(output_buffer)
            cleaned = clean_output(raw_output)
            print(cleaned)
        
        return 0 if work_started else 1
        
    except Exception as e:
        print(f"\nError: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        if child.isalive():
            child.terminate(force=True)
        return 1


def main():
    parser = argparse.ArgumentParser(description='Wrapper for cursor-agent')
    parser.add_argument('--model', '-m', required=True, help='Model to use')
    parser.add_argument('-p', '--prompt', required=True, help='Prompt text or file path')
    parser.add_argument('-f', '--flag', action='store_true', help='(ignored)')
    parser.add_argument('--timeout', type=int, default=900, help='Overall timeout (default: 600s)')
    parser.add_argument('--idle-timeout', type=int, default=60, help='Idle timeout (default: 60s)')
    parser.add_argument('-v', '--verbose', action='store_true', help='Debug output')
    parser.add_argument('--raw', action='store_true', help='Output raw TUI (default: clean output)')
    parser.add_argument('-c', '--clean', action='store_true', help='(deprecated, now default)')
    
    args = parser.parse_args()
    prompt = read_prompt_file(args.prompt)
    
    exit_code = run_cursor_agent(
        model=args.model,
        prompt=prompt,
        timeout=args.timeout,
        idle_timeout=args.idle_timeout,
        verbose=args.verbose,
        clean=not args.raw
    )
    sys.exit(exit_code)


if __name__ == '__main__':
    main()
