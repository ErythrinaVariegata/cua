"""Tests for --api-base argument forwarding through CLI commands.

This module verifies that the --api-base argument is correctly propagated
through various execution modes (task, dataset, wait, detached, etc).
"""

from pathlib import Path
from unittest.mock import MagicMock, patch
import subprocess
import sys

import pytest


class TestApiBaseForwarding:
    """Test suite for --api-base argument forwarding."""

    def test_task_detached_mode_includes_api_base(self):
        """Verify task detached mode forwards --api-base to subprocess."""
        from cua_bench.cli.commands import run
        
        with patch('subprocess.Popen') as mock_popen:
            # Setup mock
            mock_proc = MagicMock()
            mock_popen.return_value = mock_proc
            
            # Create args with api_base set
            args = MagicMock()
            args.task_path = Path("/tmp/test_task")
            args.wait = False  # Detached mode
            args.run_id = "test_run_123"
            args.session_id = None
            args.variant_id = 0
            args.agent = None
            args.agent_import_path = None
            args.model = None
            args.max_steps = None
            args.api_base = "http://custom-api.example.com:5000"
            args.oracle = False
            args.platform = None
            args.image = None
            args.output_dir = None
            args.vnc_port = None
            args.api_port = None
            args.debug = False
            args.provider_type = None
            args.dev_paths = None
            args.verbose = False
            
            with patch('pathlib.Path.exists', return_value=True):
                with patch('tempfile.TemporaryDirectory') as mock_tempdir:
                    mock_tempdir.return_value.__enter__.return_value = "/tmp/mock_temp"
                    with patch('uuid.uuid4', return_value=MagicMock(hex="run_id")):
                        try:
                            run.execute_task(args)
                        except Exception:
                            pass  # We just want to capture the command
            
            # Verify subprocess was called with --api-base
            assert mock_popen.called, "Popen should have been called"
            cmd = mock_popen.call_args[0][0]
            
            assert "--api-base" in cmd, "--api-base should be in subprocess command"
            api_base_idx = cmd.index("--api-base")
            assert cmd[api_base_idx + 1] == "http://custom-api.example.com:5000"

    def test_dataset_detached_mode_includes_api_base(self):
        """Verify dataset detached mode forwards --api-base to subprocess."""
        from cua_bench.cli.commands import run
        
        with patch('subprocess.Popen') as mock_popen:
            # Setup mock
            mock_proc = MagicMock()
            mock_popen.return_value = mock_proc
            
            # Create args with api_base set
            args = MagicMock()
            args.dataset_path = Path("/tmp/test_dataset")
            args.wait = False  # Detached mode
            args.run_id = "test_run_456"
            args.agent = None
            args.agent_import_path = None
            args.model = None
            args.max_steps = None
            args.api_base = "http://custom-api.example.com:8000"
            args.oracle = False
            args.platform = None
            args.image = None
            args.output_dir = None
            args.max_parallel = 4
            args.max_variants = None
            args.task_filter = None
            args.provider_type = None
            args.dev_paths = None
            args.verbose = False
            
            with patch('pathlib.Path.exists', return_value=True):
                with patch('tempfile.TemporaryDirectory') as mock_tempdir:
                    mock_tempdir.return_value.__enter__.return_value = "/tmp/mock_temp"
                    with patch('uuid.uuid4', return_value=MagicMock(hex="run_id")):
                        try:
                            run.execute_dataset(args)
                        except Exception:
                            pass  # We just want to capture the command
            
            # Verify subprocess was called with --api-base
            assert mock_popen.called, "Popen should have been called"
            cmd = mock_popen.call_args[0][0]
            
            assert "--api-base" in cmd, "--api-base should be in subprocess command"
            api_base_idx = cmd.index("--api-base")
            assert cmd[api_base_idx + 1] == "http://custom-api.example.com:8000"

    def test_api_base_not_forwarded_when_not_set(self):
        """Verify --api-base is not added to command when not provided."""
        from cua_bench.cli.commands import run
        
        with patch('subprocess.Popen') as mock_popen:
            # Setup mock
            mock_proc = MagicMock()
            mock_popen.return_value = mock_proc
            
            # Create args WITHOUT api_base
            args = MagicMock()
            args.task_path = Path("/tmp/test_task")
            args.wait = False
            args.run_id = "test_run_789"
            args.session_id = None
            args.variant_id = 0
            args.agent = None
            args.agent_import_path = None
            args.model = None
            args.max_steps = None
            args.api_base = None  # Not set
            args.oracle = False
            args.platform = None
            args.image = None
            args.output_dir = None
            args.vnc_port = None
            args.api_port = None
            args.debug = False
            args.provider_type = None
            args.dev_paths = None
            args.verbose = False
            
            with patch('pathlib.Path.exists', return_value=True):
                with patch('tempfile.TemporaryDirectory') as mock_tempdir:
                    mock_tempdir.return_value.__enter__.return_value = "/tmp/mock_temp"
                    with patch('uuid.uuid4', return_value=MagicMock(hex="run_id")):
                        try:
                            run.execute_task(args)
                        except Exception:
                            pass
            
            # Verify subprocess was called but WITHOUT --api-base
            assert mock_popen.called
            cmd = mock_popen.call_args[0][0]
            assert "--api-base" not in cmd, "--api-base should not be in command when not set"

    def test_api_base_consistency_across_modes(self):
        """Verify api_base handling is consistent between task and dataset modes."""
        # This is more of a code inspection test
        # Both should use: if getattr(args, "api_base", None):
        #                     cmd.extend(["--api-base", args.api_base])
        
        with open(Path(__file__).parent.parent / "cli" / "commands" / "run.py") as f:
            content = f.read()
        
        # Both patterns should exist in the file
        pattern_task = 'if getattr(args, "api_base", None):'
        
        # Count occurrences (should be at least in task and dataset modes,
        # plus potentially in wait mode)
        count = content.count(pattern_task)
        assert count >= 2, f"Expected at least 2 api_base forwarding checks, found {count}"
        
        # Verify the pattern is followed by the correct extension
        pattern_full = 'if getattr(args, "api_base", None):\n            cmd.extend(["--api-base", args.api_base])'
        count_full = content.count(pattern_full)
        assert count_full >= 2, f"Expected at least 2 complete api_base forwarding patterns, found {count_full}"
