const https = require('https');
const fs = require('fs');
const path = require('path');

const headers = { 'User-Agent': 'NodeJS/GithubSearch' };

function downloadJSON(url, dest) {
    https.get(url, { headers }, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
            fs.writeFileSync(dest, data);
            console.log('Downloaded to', dest);
        });
    }).on('error', (err) => console.error(err));
}

// Just an example URL for Confetti:
// I'll grab a known one from lottiefiles/lottie-react-native if it exists, or similar
const url1 = "https://raw.githubusercontent.com/LottieFiles/lottie-react-native/master/example/js/animations/Watermelon.json";

// Query Github API for confetti lottie json
https.get('https://api.github.com/search/code?q=filename:confetti.json+lottie+in:path', { headers }, (res) => {
    let data = '';
    res.on('data', chunk => data += chunk);
    res.on('end', () => {
        try {
            const json = JSON.parse(data);
            if (json.items && json.items.length > 0) {
                const item = json.items[0];
                const rawUrl = item.html_url.replace('/blob/', '/raw/');
                downloadJSON(rawUrl, path.join(__dirname, 'assets', 'animations', 'premium_reward.json'));
            }
        } catch (e) { }
    });
});

https.get('https://api.github.com/search/code?q=filename:sunset.json+lottie', { headers }, (res) => {
    let data = '';
    res.on('data', chunk => data += chunk);
    res.on('end', () => {
        try {
            const json = JSON.parse(data);
            if (json.items && json.items.length > 0) {
                const item = json.items[0];
                const rawUrl = item.html_url.replace('/blob/', '/raw/');
                downloadJSON(rawUrl, path.join(__dirname, 'assets', 'animations', 'sunset.json'));
            }
        } catch (e) { }
    });
});

https.get('https://api.github.com/search/code?q=filename:sun.json+moon+lottie', { headers }, (res) => {
    let data = '';
    res.on('data', chunk => data += chunk);
    res.on('end', () => {
        try {
            const json = JSON.parse(data);
            if (json.items && json.items.length > 0) {
                const item = json.items[0];
                const rawUrl = item.html_url.replace('/blob/', '/raw/');
                downloadJSON(rawUrl, path.join(__dirname, 'assets', 'animations', 'theme_toggle.json'));
            }
        } catch (e) { }
    });
});
