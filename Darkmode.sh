#!/bin/bash
#
## macOS Dark Mode at sunset
## Solar times pulled from Yahoo Weather API
## Author: katernet ## Version 1.4

## Global variables ##
darkdir=~/Library/Application\ Support/darkmode # darkmode directory
plistR=~/Library/LaunchAgents/io.github.katernet.darkmode.sunrise.plist # Launch Agent plist locations
plistS=~/Library/LaunchAgents/io.github.katernet.darkmode.sunset.plist

## Functions ##

# Set dark mode - Sunrise = off Sunset = on
darkMode() {
	case $1 in
		off) 
			# Disable dark mode
			osascript -e '
			tell application id "com.apple.systemevents"
				tell appearance preferences
					if dark mode is true then
						set dark mode to false
					end if
				end tell
			end tell
			'
			if ls /Applications/Alfred*.app >/dev/null 2>&1; then # If Alfred installed
				osascript -e 'tell application "Alfred 3" to set theme "Alfred"' 2> /dev/null # Set Alfred default theme
			fi
			# Get sunset launch agent start interval time
			plistSH=$(/usr/libexec/PlistBuddy -c "Print :StartCalendarInterval:Hour" "$plistS" 2> /dev/null)
			plistSM=$(/usr/libexec/PlistBuddy -c "Print :StartCalendarInterval:Minute" "$plistS" 2> /dev/null)
			if [ -z "$plistSH" ] && [ -z "$plistSM" ]; then # If plist solar time vars are empty
				editPlist add "$setH" "$setM" "$plistS" # Run add solar time plist function
			elif [[ "$plistSH" -ne "$setH" ]] || [[ "$plistSM" -ne "$setM" ]]; then # If launch agent times and solar times differ
				editPlist update "$setH" "$setM" "$plistS" # Run update solar time plist function
			fi
			# Run solar query on first day of week
			if [ "$(date +%u)" = 1 ]; then
				solar
			fi
			;;
		on)
			# Enable dark mode
			osascript -e '
			tell application id "com.apple.systemevents"
				tell appearance preferences
					if dark mode is false then
						set dark mode to true
					end if
				end tell
			end tell
			'
			if ls /Applications/Alfred*.app >/dev/null 2>&1; then
				osascript -e 'tell application "Alfred 3" to set theme "Alfred Dark"' 2> /dev/null # Set Alfred dark theme
			fi
			# Get sunrise launch agent start interval
			plistRH=$(/usr/libexec/PlistBuddy -c "Print :StartCalendarInterval:Hour" "$plistR" 2> /dev/null)
			plistRM=$(/usr/libexec/PlistBuddy -c "Print :StartCalendarInterval:Minute" "$plistR" 2> /dev/null)
			if [ -z "$plistRH" ] && [ -z "$plistRM" ]; then
				editPlist add "$riseH" "$riseM" "$plistR"
			elif [[ "$plistRH" -ne "$riseH" ]] || [[ "$plistRM" -ne "$riseM" ]]; then
				editPlist update "$riseH" "$riseM" "$plistR"
			fi
			;;
	esac
}

# Solar query
solar() {
	# Set location
	# Get city and nation from http://ipinfo.io
	loc=$(curl -s ipinfo.io/geo | awk -F: '{print $2}' | awk 'FNR ==3 {print}' | sed 's/[", ]//g')
	nat=$(curl -s ipinfo.io/geo | awk -F: '{print $2}' | awk 'FNR ==5 {print}' | sed 's/[", ]//g')
	# Get solar times
	riseT=$(curl -s "https://query.yahooapis.com/v1/public/yql?q=select%20astronomy.sunrise%20from%20weather.forecast%20where%20woeid%20in%20(select%20woeid%20from%20geo.places(1)%20where%20text%3D%22${loc}%2C%20${nat}%22)&format=json&env=store%3A%2F%2Fdatatables.org%2Falltableswithkeys" | awk -F\" '{print $22}')
	setT=$(curl -s "https://query.yahooapis.com/v1/public/yql?q=select%20astronomy.sunset%20from%20weather.forecast%20where%20woeid%20in%20(select%20woeid%20from%20geo.places(1)%20where%20text%3D%22${loc}%2C%20${nat}%22)&format=json&env=store%3A%2F%2Fdatatables.org%2Falltableswithkeys" | awk -F\" '{print $22}')
	# Convert times to 24H
	riseT24=$(date -jf "%I:%M %p" "${riseT}" +"%H:%M" 2> /dev/null)
	setT24=$(date -jf "%I:%M %p" "${setT}" +"%H:%M" 2> /dev/null)
	# Store times in database
	sqlite3 "$darkdir"/solar.db <<EOF
	CREATE TABLE IF NOT EXISTS solar (id INTEGER PRIMARY KEY, time VARCHAR(5));
	INSERT OR IGNORE INTO solar (id, time) VALUES (1, '$riseT24'), (2, '$setT24');
	UPDATE solar SET time='$riseT24' WHERE id=1;
	UPDATE solar SET time='$setT24' WHERE id=2;
EOF
	# Log
	echo "$(date +"%d/%m/%y %T")" darkmode: Solar query stored - Sunrise: "$(sqlite3 "$darkdir"/solar.db 'SELECT time FROM solar WHERE id=1;' "")" Sunset: "$(sqlite3 "$darkdir"/solar.db 'SELECT time FROM solar WHERE id=2;' "")" >> ~/Library/Logs/io.github.katernet.darkmode.log
}

# Deploy launch agents
launch() {
	shdir="$(cd "$(dirname "$0")" && pwd)" # Get script path
	mkdir ~/Library/LaunchAgents 2> /dev/null; cd "$_" || return # Create LaunchAgents directory (if required) and cd there
	# Setup launch agent plists
	/usr/libexec/PlistBuddy -c "Add :Label string io.github.katernet.darkmode.sunrise" "$plistR" 1> /dev/null
	/usr/libexec/PlistBuddy -c "Add :Program string ${shdir}/darkmode.sh" "$plistR"
	/usr/libexec/PlistBuddy -c "Add :Label string io.github.katernet.darkmode.sunset" "$plistS" 1> /dev/null
	/usr/libexec/PlistBuddy -c "Add :Program string ${shdir}/darkmode.sh" "$plistS"
	# Load launch agents
	launchctl load "$plistR"
	launchctl load "$plistS"
}

# Edit launch agent solar times
editPlist() {
	case $1 in
		add)
			# Add solar times to launch agent plist
			/usr/libexec/PlistBuddy -c "Add :StartCalendarInterval:Hour integer $2" "$4"
			/usr/libexec/PlistBuddy -c "Add :StartCalendarInterval:Minute integer $3" "$4"
			# Reload launch agent
			launchctl unload "$4"
			launchctl load "$4"
			;;
		update)
			# Update launch agent plist solar times
			/usr/libexec/PlistBuddy -c "Set :StartCalendarInterval:Hour $2" "$4"
			/usr/libexec/PlistBuddy -c "Set :StartCalendarInterval:Minute $3" "$4"
			# Reload launch agent
			launchctl unload "$4"
			launchctl load "$4"
			;;
	esac
}

# Error logging
log() {
	while IFS='' read -r line; do
		echo "$(date +"%D %T") $line" >> ~/Library/Logs/io.github.katernet.darkmode.log
	done
}

## Config ##

# Error log
exec 2> >(log)

# Create darkmode directory if doesn't exist
if [ ! -d "$darkdir" ]; then
	mkdir "$darkdir"
	solar
fi

# Deploy launch agents if don't exist
if [ ! -f "$plistR" ] || [ ! -f "$plistS" ]; then
	launch
fi

# Get sunrise and sunset hrs and mins. Strip leading 0 with sed.
riseH=$(sqlite3 "$darkdir"/solar.db 'SELECT time FROM solar WHERE id=1;' "" | head -c2 | sed 's/^0//')
riseM=$(sqlite3 "$darkdir"/solar.db 'SELECT time FROM solar WHERE id=1;' "" | tail -c3 | sed 's/^0//')
setH=$(sqlite3 "$darkdir"/solar.db 'SELECT time FROM solar WHERE id=2;' "" | head -c2 | sed 's/^0//')
setM=$(sqlite3 "$darkdir"/solar.db 'SELECT time FROM solar WHERE id=2;' "" | tail -c3 | sed 's/^0//')

# Current 24H time hr and min
timeH=$(date +"%H" | sed 's/^0*//')
timeM=$(date +"%M" | sed 's/^0*//')

## Code ##

# Solar conditions
if [[ "$timeH" -ge "$riseH" && "$timeH" -lt "$setH" ]]; then
	# Sunrise
	if [[ "$timeH" -ge $((riseH+1)) || "$timeM" -ge "$riseM" ]]; then
		darkMode off
	# Sunset	
	elif [[ "$timeH" -ge "$setH" && "$timeM" -ge "$setM" ]] || [[ "$timeH" -le "$riseH" && "$timeM" -lt "$riseM" ]]; then 
		darkMode on
	fi
# Sunset		
elif [[ "$timeH" -ge 0 && "$timeH" -lt "$riseH" ]]; then
	darkMode on
# Sunrise	
elif [[ "$timeH" -eq "$setH" && "$timeM" -lt "$setM" ]]; then
	darkMode off
# Sunset	
else
	darkMode on
fi
