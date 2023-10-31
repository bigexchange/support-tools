# Log Gathering Script for BigID

This script simplifies the process of gathering logs for BigID in a Kubernetes environment. It allows users to collect both current and previous logs from pods, making troubleshooting and analysis more efficient.

## Usage

1. Ensure that `kubectl` is installed and configured properly on your system.
2. Clone the repository to your local machine.
3. Customize the script as needed for your specific environment.
4. Run the script and follow the interactive prompts to collect logs from the desired pods.

## Features

- Select a Kubernetes namespace to target specific pods.
- Choose a directory for storing log files, making organization and access easier.
- Capture logs from restarted pods, aiding in the debugging of issues that might have caused pod restarts.
- Option to select logs from all pods or only specific types of pods.
- Ability to choose individual containers within pods to collect logs for granular analysis.

## Dependencies

- `kubectl`: Ensure that you have `kubectl` properly configured and accessible in your terminal environment.

To quickly execute the script, run the following command:

```bash
bash <(curl -s https://raw.githubusercontent.com/bigexchange/support-tools/main/scripts/bigid_log_gather.sh)
```

## Compatibility

This script is compatible with any Linux or macOS system where `bash` is available.

## License

This project is licensed under the terms of the MIT license. See the [LICENSE](LICENSE) file for details.
