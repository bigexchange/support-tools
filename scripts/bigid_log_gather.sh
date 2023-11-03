#!/bin/bash
# Script Name: podLogs.sh
# Author: kmccready@bigid.com
# Description: The following script streamlines gathering current or previous kubernetes pod logs.

# Previous Versions:
    # Version 1.0-1.3 Sept 1-5 2023
        # Rough concept of the script.
        # Basic commands laid out with no functions, to get an idea of how I wanted this script to run.
        # Working script from top to bottom, but did not capture previous logs, or allow reiteration. 

    # Version 2.0-2.6 Sept 5 Oct 8 2023
        # Re-wrote the script to use functions.
        # Added the ability to grab previous logs from restarted pods.
        # Added error detection for RBAC.
        # Added error detection and fallbacks for most functions.
        # Added the ability to select all pods.
        # Added the ability to start the script back over from after namespace selection.

    # Version 3.0-3.7 Oct 9-20 2023
        # Re-wrote the script from version two to be more linear.
        # Functions now follow the general path and flow of the script to make it less messy.
        # Added log storage directory location choice.
        # Added a function to prevent running the same lines of code multiple times in different locations.
        # Re-wrote the script to make it more organized and easier to follow.
        # Added the prompt to automatically compress the logs that were just gathered.
        # Fixed the Namespace issue with RBAC and how it would infinite loop no matter what was entered.
        # Fixed the previous logs "Select_All" from gathering EVERY pod and not just the restarted ones.
        # Fixed the getContainerLogs function to be formatted correctly with if else statement.
    # Version 3.8 Oct 21 2023
        # Added a feature to add the kubectl describe $pod to the end of the corresponding pods logs.
            # To prevent further gating behind RBAC, this will only work if the user has describe privileges.
                # kubectl describe $pod -n $NAMESPACE
        # Had the logLocation display the exact path where it will be saved to instead of saying "TodaysDate"

# Current Version: 
    # Version 3.9 Nov 2 2023
        # Fixed the wording on all the select statements to be less confusing.
        # Fixed the issue with the restarted pods not correctly looping through and a allowing the user to select the desired label.

#variables for colors
reset="\e[0m"
# red="\e[91m"
green="\e[92m"
cyan="\e[96m"
magenta="\e[95m"

# Bold High Intensity
# BIBlack="\e[1;90m"      # Black
BIRed="\e[1;91m"   # Red
BIGreen="\e[1;92m" # Green
BIYellow="\e[1;93m"     # Yellow
# BIBlue="\e[1;94m"       # Blue
BIPurple="\e[1;95m" # Purple
BICyan="\e[1;96m"   # Cyan
BIWhite="\e[1;97m"  # White

#Blinking
blink="\e[5m"

# log is used to filter error statuses (essentially beefed up echo)
log() {
    msg=$1
    level=$2
    case $level in
    "error")
        msg="${BIRed}[ERROR] ${msg}${reset}"
        ;;
    esac
    echo -e "${msg}"
}

# Global Variables
NAMESPACE=""
SELECTED_LABELS=""
RESTARTEDPODSEXIST=false
namespace_list=$(kubectl get namespaces -o custom-columns=:metadata.name --no-headers)
namespace_list_exit_code=$?

# We use the exit code to filter out when namespace permissions fail

# Check if kubectl is available
if ! command -v kubectl &>/dev/null; then
    log "Error: kubectl command not found. Make sure it's installed and in your PATH." "error"
    exit 1
fi

#1. Ask for the NameSpace
# Namespace permission check
selectNamespace() {
    if [ "$namespace_list_exit_code" -gt 0 ]; then
        log "Permission denied. You do not have the required permissions to list namespaces." "error"
        while true; do
            read -rp "Enter a namespace manually: " manual_namespace
            if kubectl get pods -n "$manual_namespace" &>/dev/null; then
                NAMESPACE="$manual_namespace"
                break
            else
                log "Namespace '$manual_namespace' does not exist or cannot be accessed. Please enter a valid namespace. " "error"
                continue
            fi
        done
    else
        nameSpaceInput
    fi
}

# check to see if a namespace is valid
isNameSpaceValid() {
    getPod=$(kubectl get pods -n "$1" 2>&1)
    if [[ "$getPod" == *"No resources found"* ]]; then
        # kubectl get pods with a wrong namespace will exit with code 0.
        # 2>&1 will send the command to standard error, which can be referenced for the "No resources found" string
        return 1
    else
        return 0
    fi
}

# called from selectNamespace if permissions do not fail out.
nameSpaceInput() {
    # Create namespace list
    IFS=$'\n' read -rd '' -a options <<<"$namespace_list"
    options+=("Desired namespace not listed")
    log "${BICyan}Select a namespace:${reset}"
    for i in "${!options[@]}"; do
        log "$((i + 1)): ${options[$i]}"
    done
    # Option selection in case desired namespace is not shown.
    while true; do
        read -rp "Enter selection: " choice
        if [[ "$choice" -ge 1 && "$choice" -le ${#options[@]} ]]; then
            index=$((choice - 1))
            NAMESPACE="${options[$index]}"
            if [ "$NAMESPACE" == "Desired namespace not listed" ]; then
                while true; do
                    read -rp "Enter namespace manually: " manual_namespace
                    if isNameSpaceValid "$manual_namespace"; then
                        NAMESPACE="$manual_namespace"
                        break # Add this line to exit the loop
                    else
                        log "Namespace '$manual_namespace' does not exist or cannot be accessed. Please enter a valid namespace. " "error"
                        continue
                    fi
                done
            fi
            log "${BIPurple}Selected namespace: $NAMESPACE ${reset}"
            break
        else
            log "Invalid choice. Please select a valid number." "error"
        fi
    done
}

#2. Ask if you want to save to a currently existing directory. Else it will be saved to /tmp/<namespace>/<date>
# Additional Log saving information and compression.

logLocation() {
    logDir=""
    log "\n${BIRed}====================================================================${reset}"
    log "${BIWhite}Logs will be saved by default to ${BIGreen}/tmp/$NAMESPACE/bigidLogs_$(date +%d-%b-%Y))${reset}"
    log "${BIRed}====================================================================${reset}"
    log "${BICyan}Would you like to specify a different directory for saving logs? ${reset}(y/N)"
    read -r directoryChoice
    if [[ "$directoryChoice" = y ]]; then
        while true; do
            read -rp "Enter the target directory: " manualDirectory
            if [ ! -d "$manualDirectory" ]; then
                log "Directory doesn't exist" "error"
                continue
            else
                logDir="$manualDirectory"
                log "${BIPurple}~*~*~*~*~*~*~*~*~*~*~*~*${BIWhite}Logs will be saved to ${BIGreen}$logDir${BIPurple}*~*~*~*~*~*~*~*~*~*~*~*~${reset}\n"
                break
            fi
        done
    else
        # define the directory where the logs will be written to.
        logDir="/tmp/$NAMESPACE/bigidLogs_$(date +%d-%b-%Y)"
        # Check if the directory exists
        if [ ! -d "$logDir" ]; then
            # Directory doesn't exist, so create it
            mkdir -p "$logDir"
        fi
        log "${BIPurple}~*~*~*~*~*~*~*~*~*~*~*~*${BIWhite}Logs will be saved to ${BIGreen}$logDir${BIPurple}*~*~*~*~*~*~*~*~*~*~*~*~${reset}\n"
    fi
}

#3. Ask if you want to gather previous logs from restarted pods

echoRestartedPods() {
    local restartedPods
    restartedPods=$(kubectl get pods -n "$NAMESPACE" | awk '$4>0')
    # this will only grab pods where restarts are greater than 0.
    if [[ -n "$restartedPods" ]]; then
        log "\t\t${BIGreen}${blink}The following pods have been restarted${reset}"
        log "${BIRed}========================================================================="
        log "${BIWhite}$restartedPods${reset}"
        log "${BIRed}=========================================================================\n"
        log "${BICyan}Would you like to gather previous logs from ${BIRed}restarted pods?${reset} (y/N)"
        read -r previousLogs
        if [[ "$previousLogs" = "y" ]]; then
            CHECKPREVIOUSLOGS=true
        fi
    fi
}

#4. Ask if you want to gather logs from all pods/all pods of the same type.

selectLabels() {
    podLabels=""
    if [[ "$CHECKPREVIOUSLOGS" = true ]]; then
        podLabels=$(kubectl get pods -n $NAMESPACE --no-headers -o 'custom-columns=NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount,LABELS:metadata.labels' | awk '$2 != "<none>"' | awk '{print$3}' | awk 'BEGIN {FS = "[[, ]"};{print$2}' | sed 's/:/=/g' | sort -u)
    else
        # This gets the first unique label for each pod
        podLabels=$(kubectl get pods -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.labels" | awk 'BEGIN {FS = "[[, ]"};{print$2}' | sed 's/:/=/g' | sort -u)
    fi

    podLabels=$(echo "$podLabels Select_All" | xargs)

    # have the user select the SELECTED_LABELS
    log "${BICyan}Select a label:${reset}"
    select label in $podLabels; do
        if [[ "$label" = "Select_All" ]]; then
            SELECTED_LABELS="$podLabels"
            break
        elif [[ -n "$label" ]]; then
            SELECTED_LABELS="$label"
            break
        else
            log "Invalid selection." "error"
        fi
    done
}


#5. Ask for the Container if SelectAll is not chosen
# function that drills down to the container level and grabs the logs

getContainerLogs() {
    # have the user select the pod
    log "Select a pod:"
    if [[ "$CHECKPREVIOUSLOGS" = true ]]; then
        pods=$(kubectl get pods --no-headers -n "$NAMESPACE" | awk '$4>0' | awk '{print $1}')
    else
        pods=$(kubectl get pods -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name")
    fi
    select pod in $pods; do
        if [[ -n "$pod" ]]; then
            break
        else
            log "Invalid selection." "error"
        fi
    done
    # get a list of containers in the pod
    CONTAINERS=$(kubectl get pods -n "$NAMESPACE" "$pod" -o jsonpath='{.spec.containers[*].name}')
    # have the user select the container
    log "${BICyan}Select a container:${reset}"
    select containerName in $CONTAINERS; do
        if [[ -n "$containerName" ]]; then
            break
        else
            log "Invalid selection." "error"
        fi
    done
    fetchLogs "$pod" "$containerName"
    # Ask to grab more logs in the same namespace
    finishLine
}

#6  Save logs to the directory

# Called at the end to save logs.
fetchLogs() {
    pod=$1
    containerName=$2
    canDescribe=""
    if kubectl describe pod -n "$NAMESPACE" &>/dev/null; then
        canDescribe=true
    fi
    log "-------------------------"
    if [[ "$CHECKPREVIOUSLOGS" = true ]]; then
        log "Grabbing logs from pod ${green}$pod${reset} and container ${magenta}${containerName}${reset} with the previous flag"
        filename="${pod}-${containerName}_Previous_$(date +%d-%b-%Y_%H_%M:%S).log"
        kubectl logs -n "$NAMESPACE" "$pod" -c "$containerName" --previous >>"${logDir}/${filename}" || log "Could not grab logs from pod $pod with the previous flag, container $containerName does not exist" "error"
        log "Logs saved to ${green}${logDir}/${magenta}${filename}${reset}"
    else
        log "Grabbing logs from pod ${green}${pod}${reset} and container ${magenta}${containerName}${reset}"
        filename="${pod}-${containerName}-$(date +%d-%b-%Y_%H_%M:%S).log"
        kubectl logs -n "$NAMESPACE" "$pod" -c "$containerName" >>"${logDir}/${filename}" || log -e "Could not grab logs from pod $pod, container $containerName does not exist" "error"
        log "Logs saved to ${green}${logDir}/${magenta}${filename}${reset}"
    fi
    # Append kubectl describe to the end of the log file if they have permissions to do so.
    if [[ "$canDescribe" = true ]]; then
            echo "" >> "${logDir}/${filename}"
            echo "################### kubectl describe for $pod ###################" >> "${logDir}/${filename}"
            echo "" >> "${logDir}/${filename}"
            kubectl describe pod -n "$NAMESPACE" "$pod" >>"${logDir}/${filename}" || log -e "Could not grab pod description from pod $pod" "error"
    fi
    log "-------------------------"
}

#7. Ask if yo uwant to gather more logs in the same namespace.
finishLine() {
    # Ask to grab more logs in the same namespace
    log "${BICyan}Would you like to grab more logs from the same Namespace? ${reset}(y/N) "
    read -r reRun
    if [[ "${reRun,,}" = "y" ]]; then
        main
    else
        log "${BICyan}Would you like to compress the logs? ${BIRed}(Note this will compress ALL .log files to a tar.gz in $logDir) ${reset}(y/N) "
        read -r compressChoice
        if [[ "${compressChoice,,}" = "y" ]]; then
            tarFiles
        else
            exit 0
        fi
    fi
}

#8. Compress the files in the specified directory.n
tarFiles() {
    currentDirectory="$(pwd)"
    cd "$logDir" || return
    tar czf bigidLogs-"$(date +%d-%b-%Y)".tar.gz --remove-files --no-recursion ./*.log
    cd "$currentDirectory" || return
    log "${BIPurple}Logs have been compressed to ${green}$logDir/bigidLogs-$(date +%d-%b-%Y).tar.gz ${reset}"
    exit 0
}

#8: Main script

main() {
    # Main function where we will run through the script and allow for callbacks.
    CHECKPREVIOUSLOGS=false
    echoRestartedPods
    log "${BIWhite}Logs will be gathered from ${BIRed}one${BIWhite} selected ${BIGreen}pod/container${BIWhite} by default.${reset}"
    log "${BICyan}Do you want to grab logs from all pods of the same type instead?${BIGreen}(Example: all bigid-scanner pods)${reset} (y/N)"
    read -r labelAnswer
    if [[ "$labelAnswer" = "y" ]]; then
        selectLabels
    else
        getContainerLogs
        exit 0
    fi

    allPods=""

    # get a list of all pods that have the SELECTED_LABELS
    # Called from selectLabels
    for label in $SELECTED_LABELS; do
        allPods+=" $(kubectl get pods -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" -l "$label")"
    done
    restartedPods=$(kubectl get pods --no-headers -n "$NAMESPACE" | awk '$4>0' | awk '{print $1}')
    restartedPodsWithSELECTED_LABELS=""
    # remove pods from allPods that have not been restarted
    for pod in $allPods; do
        for restartedPod in $restartedPods; do
            if [[ "$pod" = "$restartedPod" ]]; then
                restartedPodsWithSELECTED_LABELS="$restartedPodsWithSELECTED_LABELS $pod"
            fi
        done
    done
    podsToSearch=""
    if [ "$CHECKPREVIOUSLOGS" = true ]; then
        for pod in "${restartedPodsWithSELECTED_LABELS[@]}"; do
            podsToSearch+=" $pod"
        done
    else
        for pod in "${allPods[@]}"; do
            podsToSearch+=" $pod"
        done
    fi

    # Convert podsToSearch to a space separated string with xargs.
    podsToSearch=$(echo "$podsToSearch" | xargs)

    # Get a list of the containers in teh very first pod selected.
    firstPod=$(echo "$podsToSearch" | awk '{print $1}')

    if [[ "$SELECTED_LABELS" == *"Select_All"* ]]; then
        if [ "$CHECKPREVIOUSLOGS" == true ]; then
            podsToSearch="$restartedPods"
        else
            podsToSearch=$(kubectl get pods -n "$NAMESPACE" --no-headers | awk '{print$1}')
        fi
    fi

    echo "---------------------------------"
    echo "Attempting to grab logs from the following pods:"
    echo "$podsToSearch"
    echo "---------------------------------"

    # if the user selected Select_All, grab the logs from all containers in each pod
    if [[ "$SELECTED_LABELS" == *"Select_All"* ]]; then
        for pod in $podsToSearch; do
            for container in $(kubectl get pods -n "$NAMESPACE" "$pod" -o jsonpath='{.spec.containers[*].name}'); do
                fetchLogs "$pod" "$container"
            done
        done
        finishLine
    fi

    # have the user select the container name from the first pod in podsToSearch
    log "${BICyan}Select a container: ${reset}"
    select containerName in $(kubectl get pods -n "$NAMESPACE" "$firstPod" -o jsonpath='{.spec.containers[*].name}'); do
        if [[ -n "$containerName" ]]; then
            break
        else
            log "Invalid selection." "error"
        fi
    done
    # for each pod in the list of pods to search, grab the logs
    for pod in $podsToSearch; do
        fetchLogs "$pod" "$containerName"
    done

    finishLine
}
selectNamespace
logLocation
main
