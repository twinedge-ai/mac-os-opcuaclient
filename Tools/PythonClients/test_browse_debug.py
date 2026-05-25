#!/usr/bin/env python3

import asyncio
import subprocess
import time
import signal

async def test_browse():
    """
    Test the Swift OPC UA client browse functionality by watching console output
    """
    
    print("Testing Swift OPC UA client browse functionality...")
    print("Starting console monitor to capture debug output...")
    
    # Monitor system logs for our app's debug output
    log_process = subprocess.Popen([
        'log', 'stream', '--predicate', 'senderImagePath contains "OpcUaClient"', 
        '--style', 'compact'
    ], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    
    try:
        # Let it run for a bit to capture any browse operations
        print("Monitoring logs for 30 seconds...")
        print("If you perform browse operations in the Swift app, debug output should appear below:")
        print("-" * 80)
        
        start_time = time.time()
        while time.time() - start_time < 30:
            if log_process.poll() is not None:
                break
                
            output = log_process.stdout.readline()
            if output:
                print(f"LOG: {output.strip()}")
            
            await asyncio.sleep(0.1)
            
    except KeyboardInterrupt:
        print("\nStopping log monitor...")
    finally:
        log_process.terminate()
        try:
            log_process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            log_process.kill()

if __name__ == "__main__":
    asyncio.run(test_browse())