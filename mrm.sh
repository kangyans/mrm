#!/bin/bash

# MRM - Magnetic Resonance in Medicine Paper Retriever
# This script fetches the latest papers from the Magnetic Resonance in Medicine journal
# and displays their titles and abstracts in a nicely framed format.

set -e

# Colors for better readability
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Frame characters
TOP_LEFT="┌"
TOP_RIGHT="┐"
BOTTOM_LEFT="└"
BOTTOM_RIGHT="┘"
HORIZONTAL="_"
VERTICAL="|"

# Fixed display width (adjust as needed)
DISPLAY_WIDTH=100

# Help function
show_help() {
    echo -e "${GREEN}MRM - Magnetic Resonance in Medicine Paper Retriever${NC}"
    echo
    echo "Usage: mrm [OPTIONS]"
    echo
    echo "Options:"
    echo "  -n, --num NUM       Number of papers to display (default: 10)"
    echo "  -t, --title-only    Show titles only (default: shows title and abstract)"
    echo "  -s, --search TERM   Search for specific terms"
    echo "  -h, --help          Show this help message"
    echo
    echo "Examples:"
    echo "  mrm                 Show 10 latest papers with titles and abstracts"
    echo "  mrm -n 15           Show 15 latest papers with titles and abstracts"
    echo "  mrm -t              Show 10 latest papers with titles only"
    echo "  mrm -s \"diffusion\"  Search for papers with 'diffusion' in title or abstract"
    echo
}

# Default values
NUM_PAPERS=10
SHOW_TITLE_ONLY=false
SEARCH_TERM=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -n|--num)
            NUM_PAPERS="$2"
            shift 2
            ;;
        -t|--title-only)
            SHOW_TITLE_ONLY=true
            shift
            ;;
        -s|--search)
            SEARCH_TERM="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check if required tools are installed
check_requirements() {
    local missing_tools=()
    
    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    # If there are missing tools, print error and exit
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${YELLOW}Error: Missing required tools:${NC} ${missing_tools[*]}"
        echo "Please install these tools to use mrm."
        echo "You can usually install them with your package manager, for example:"
        echo "  sudo apt install ${missing_tools[*]}  # For Debian/Ubuntu"
        echo "  sudo yum install ${missing_tools[*]}  # For CentOS/RHEL"
        echo "  brew install ${missing_tools[*]}      # For macOS with Homebrew"
        exit 1
    fi
}

# Function to clean HTML tags and special notations
clean_text() {
    local input="$1"
    
    # Remove <scp> tags while preserving content
    cleaned=$(echo "$input" | sed -E 's/<\/?scp>//g')
    
    # Replace <sub> with appropriate formatting
    cleaned=$(echo "$cleaned" | sed -E 's/<sub>([^<]+)<\/sub>/_\1/g')
    
    # Replace <sup> with appropriate formatting
    cleaned=$(echo "$cleaned" | sed -E 's/<sup>([^<]+)<\/sup>/^\1/g')
    
    # Remove any other HTML tags
    cleaned=$(echo "$cleaned" | sed -E 's/<[^>]+>//g')
    
    # Replace HTML entities
    cleaned=$(echo "$cleaned" | sed 's/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g; s/&quot;/"/g; s/&apos;/'"'"'/g')
    cleaned=$(echo "$cleaned" | sed 's/&minus;/-/g; s/&hyphen;/-/g; s/&ndash;/-/g; s/&mdash;/—/g')
    cleaned=$(echo "$cleaned" | sed 's/&#8208;/-/g; s/&#8209;/-/g; s/&#8210;/-/g; s/&#8211;/-/g; s/&#8212;/—/g')
    
    echo "$cleaned"
}

# Function to format abstracts
format_abstract() {
    local abstract="$1"
    
    # Remove "Abstract" prefix if present
    abstract=$(echo "$abstract" | sed -E 's/^Abstract//')
    
   
    # Also handle variations without the colon
    abstract=$(echo "$abstract" | sed -E 's/Purpose/\n[Purpose]:/g')
    abstract=$(echo "$abstract" | sed -E 's/Methods/\n\n[Methods]:/g')
    abstract=$(echo "$abstract" | sed -E 's/Results/\n\n[Results]:/g')
    abstract=$(echo "$abstract" | sed -E 's/Conclusion/\n\n[Conclusion]:/g')
    
    # Handle case where Purpose is the first word (no newline needed)
    abstract=$(echo "$abstract" | sed -E 's/^\n\[Purpose\]/[Purpose]/g')
    
    echo "$abstract"
}

# Function to wrap text while preserving ANSI color codes
wrap_text() {
    local text="$1"
    local prefix="$2"  # Optional prefix for each line (like indentation)
    local max_width=$((DISPLAY_WIDTH - 4))  # Account for frame and padding
    
    # If there's a prefix, reduce available width accordingly
    if [[ -n "$prefix" ]]; then
        # Calculate visible length of prefix (without color codes)
        local clean_prefix=$(echo "$prefix" | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})*)?[m|K]//g")
        max_width=$((max_width - ${#clean_prefix}))
    fi
    
    # Process each line separately (important for preserving newlines in abstract sections)
    echo "$text" | while IFS= read -r input_line || [[ -n "$input_line" ]]; do
        local line=""
        local line_visible_length=0
        
        # Skip processing if line is empty
        if [[ -z "$input_line" ]]; then
            echo ""
            continue
        fi
        
        # Process each word in the line
        for word in $input_line; do
            # Clean word for length calculation (remove ANSI codes)
            local clean_word=$(echo "$word" | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})*)?[m|K]//g")
            local word_visible_length=${#clean_word}
            
            # If adding this word would exceed max width, start a new line
            if [[ $((line_visible_length + word_visible_length + 1)) -gt $max_width && $line_visible_length -gt 0 ]]; then
                # Output the current line
                echo "${prefix}${line}"
                
                # Start new line with this word
                line="$word"
                line_visible_length=$word_visible_length
            else
                # Add word to current line
                if [[ $line_visible_length -gt 0 ]]; then
                    line="${line} ${word}"
                    line_visible_length=$((line_visible_length + 1 + word_visible_length))
                else
                    line="$word"
                    line_visible_length=$word_visible_length
                fi
            fi
        done
        
        # Output the last line if not empty
        if [[ -n "$line" ]]; then
            echo "${prefix}${line}"
        fi
    done
}

# Function to create a frame around text with fixed width
create_frame() {
    local width=$DISPLAY_WIDTH
    
    # Print top border
    printf "%s%s%s\n" "$TOP_LEFT" "$(printf '%*s' $((width-2)) | tr ' ' "$HORIZONTAL")" "$TOP_RIGHT"
    
    # Process each line of content
    while IFS= read -r line; do
        # Skip empty lines but preserve spacing
        if [[ -z "$line" ]]; then
            printf "%s %*s %s\n" "$VERTICAL" "$((width-4))" "" "$VERTICAL"
            continue
        fi
        
        # Remove ANSI codes for length calculation
        local clean_line=$(echo "$line" | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})*)?[m|K]//g")
        local visible_length=${#clean_line}
        
        # Calculate padding needed for exact alignment
        local padding=$((width - 4 - visible_length))
        
        if [[ $padding -lt 0 ]]; then
            padding=0
        fi
        
        # Print the line with vertical borders and padding
        printf "%s %s%*s %s\n" "$VERTICAL" "$line" "$padding" "" "$VERTICAL"
    done
    
    # Print bottom border
    printf "%s%s%s\n" "$BOTTOM_LEFT" "$(printf '%*s' $((width-2)) | tr ' ' "$HORIZONTAL")" "$BOTTOM_RIGHT"
}

# Function to display a paper in a fixed-width frame
display_paper() {
    local title="$1"
    local url="$2"
    local date="$3"
    local abstract="$4"
    
    # Create temporary file to store the formatted content
    local temp_file=$(mktemp)
    
    # Write date to temp file
    echo -e "${GREEN}$date${NC}" >> "$temp_file"
    echo "" >> "$temp_file"
    
    # Add title with wrapping
    echo -e "${YELLOW}Title:${NC}" >> "$temp_file"
    wrap_text "$title" "  " >> "$temp_file"
    echo "" >> "$temp_file"
    
    # Add URL with wrapping
    echo -e "${YELLOW}URL:${NC}" >> "$temp_file"
    wrap_text "$url" "  " >> "$temp_file"
    
    # Add abstract if not in title-only mode
    if [ "$SHOW_TITLE_ONLY" = false ] && [ "$abstract" != "Abstract not available" ]; then
        echo "" >> "$temp_file"
        echo -e "${YELLOW}Abstract:${NC}" >> "$temp_file"
        
        # Wrap abstract text to fit within frame while preserving section breaks
        wrap_text "$abstract" "  " >> "$temp_file"
    fi
    
    # Display the framed content
    create_frame < "$temp_file"
    
    # Clean up
    rm "$temp_file"
}

# Function to fetch papers
fetch_papers() {
    echo -e "${BLUE}Fetching latest papers from Magnetic Resonance in Medicine...${NC}"
    
    # Build the API query URL
    API_URL="https://api.crossref.org/journals/1522-2594/works"
    API_URL="${API_URL}?sort=published-online&order=desc&select=title,abstract,URL,published-online&rows=${NUM_PAPERS}"
    
    # Add search term if provided
    if [ -n "$SEARCH_TERM" ]; then
        echo -e "Searching for: ${BOLD}${SEARCH_TERM}${NC}"
        API_URL="${API_URL}&query=${SEARCH_TERM}"
    fi
    
    # Fetch data from API
    RESPONSE=$(curl -s "$API_URL")
    
    # Check if curl was successful
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to fetch data from the API.${NC}"
        exit 1
    fi
    
    # Parse and display papers
    echo "$RESPONSE" | jq -r '.message.items[] | {title: .title[0], abstract: .abstract, url: .URL, date: ."published-online"."date-parts"[0][0:3]}' | 
    jq -c '.' | while read -r paper; do
        title=$(echo "$paper" | jq -r '.title')
        url=$(echo "$paper" | jq -r '.url')
        date_parts=$(echo "$paper" | jq -r '.date | join("-")')
        
        # Clean HTML from title
        title=$(clean_text "$title")
        
        if [ "$SHOW_TITLE_ONLY" = false ]; then
            abstract=$(echo "$paper" | jq -r '.abstract // "Abstract not available"')
            
            # Clean HTML from abstract
            abstract=$(clean_text "$abstract")
            
            # Format abstract
            abstract=$(format_abstract "$abstract")
        else
            abstract="Abstract not available"
        fi
        
        # Display the paper with a fixed-width frame
        display_paper "$title" "$url" "$date_parts" "$abstract"
        
        echo ""  # Add space between papers
    done
}

# Main execution
check_requirements
fetch_papers

exit 0
