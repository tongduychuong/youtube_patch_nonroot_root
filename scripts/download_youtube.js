const fs = require("fs");
const { execFileSync } = require("child_process");

const VERSION = process.env.VERSION;

if (!VERSION) {
    console.error("ERROR: VERSION is missing");
    process.exit(1);
}

const BASE = "https://www.apkmirror.com";
const V = VERSION.replace(/\./g, "-");
const UA = "Mozilla/5.0 (Linux; Android 14; Mobile)";

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

function wget(url) {
    return execFileSync("wget", [
        "-q",
        "--max-redirect=10",
        "--timeout=60",
        "--tries=3",
        "-U", UA,
        url,
        "-O", "-"
    ], {
        encoding: "utf8",
        maxBuffer: 50 * 1024 * 1024
    });
}

function download(url, filename) {
    execFileSync("wget", [
        "-q",
        "--show-progress",
        "--max-redirect=10",
        "--timeout=180",
        "--tries=5",
        "-U", UA,
        url,
        "-O", filename
    ], { stdio: "inherit" });
}

function cleanUrl(url) {
    return url.replace(/&amp;/g, "&").replace(/amp;/g, "");
}

function absoluteUrl(url, base) {
    url = cleanUrl(url);
    if (url.startsWith("http://") || url.startsWith("https://")) return url;
    if (url.startsWith("//")) return "https:" + url;
    return new URL(url, base).href;
}

function findDownloadButton(html) {
    const patterns = [
        /downloadButton[\s\S]{0,2000}?href=["']([^"']+)["']/i,
        /<a[^>]*class=["'][^"']*downloadButton[^"']*["'][^>]*href=["']([^"']+)["']/i
    ];

    for (const p of patterns) {
        const m = html.match(p);
        if (m && m[1]) return cleanUrl(m[1]);
    }
    return null;
}

function findHere(html) {
    const patterns = [
        /href=["']([^"']+)["'][^>]*>\s*here\s*</i,
        /<a[^>]+href=["']([^"']+)["'][^>]*>\s*here\s*<\/a>/i,
        /<a[^>]+href=["']([^"']+)["'][^>]*>[\s\S]{0,300}?here[\s\S]{0,300}?<\/a>/i
    ];

    for (const p of patterns) {
        const m = html.match(p);
        if (m && m[1]) return cleanUrl(m[1]);
    }
    return null;
}

function checkFile(filename) {
    try {
        const out = execFileSync("unzip", ["-l", filename], { encoding: "utf8" });
        if (out.includes("base.apk")) return "bundle";
        if (out.includes("AndroidManifest.xml")) return "apk";
    } catch (_) {}
    return "invalid";
}

async function candidate(relativePath, number) {
    const page = `${BASE}/apk/${relativePath}`;
    const temp = `youtube-${number}.tmp`;

    console.log("\n======================================");
    console.log(`CANDIDATE ${number}/4`);
    console.log(page);
    console.log("======================================");

    try {
        let html = wget(page);

        console.log("Waiting 15 seconds for downloadButton...");
        for (let i = 15; i > 0; i--) {
            process.stdout.write(`\rWaiting ${i}s...`);
            await sleep(1000);
        }
        console.log("");

        let button = findDownloadButton(html);

        for (let retry = 0; !button && retry < 15; retry++) {
            await sleep(1000);
            html = wget(page);
            button = findDownloadButton(html);
        }

        if (!button) throw new Error("Không tìm thấy downloadButton");

        const downloadPage = absoluteUrl(button, page);
        console.log("DOWNLOAD PAGE:");
        console.log(downloadPage);

        let html2 = wget(downloadPage);

        console.log("Waiting 15 seconds for 'here'...");
        for (let i = 15; i > 0; i--) {
            process.stdout.write(`\rWaiting ${i}s...`);
            await sleep(1000);
        }
        console.log("");

        let realUrl = findHere(html2);

        for (let retry = 0; !realUrl && retry < 15; retry++) {
            await sleep(1000);
            html2 = wget(downloadPage);
            realUrl = findHere(html2);
        }

        if (!realUrl) throw new Error("Không tìm thấy link here");

        realUrl = absoluteUrl(realUrl, downloadPage);

        console.log("REAL DOWNLOAD:");
        console.log(realUrl);

        download(realUrl, temp);

        const type = checkFile(temp);
        console.log("FILE TYPE:", type);

        if (type === "bundle") {
            console.log("Bundle detected - skip.");
            fs.unlinkSync(temp);
            return false;
        }

        if (type !== "apk") {
            console.log("Invalid APK - skip.");
            if (fs.existsSync(temp)) fs.unlinkSync(temp);
            return false;
        }

        const output = `com.google.android.youtube-${VERSION}-all.apk`;
        if (fs.existsSync(output)) fs.unlinkSync(output);
        fs.renameSync(temp, output);

        console.log("NORMAL APK FOUND:", output);
        console.log("SIZE:", (fs.statSync(output).size / 1024 / 1024).toFixed(2), "MB");

        return true;
    } catch (error) {
        console.log(`Candidate ${number} failed: ${error.message}`);
        if (fs.existsSync(temp)) fs.unlinkSync(temp);
        return false;
    }
}

async function main() {
    const candidates = [
        `google-inc/youtube/youtube-${V}-release/youtube-${V}-2-android-apk-download/`,
        `google-inc/youtube/youtube-${V}-release/youtube-${V}-android-apk-download/`,
        `google-inc/youtube/youtube-${V}-release/youtube-${V}-3-android-apk-download/`,
        `google-inc/youtube/youtube-${V}-release/youtube-${V}-4-android-apk-download/`
    ];

    console.log("======================================");
    console.log("YouTube APKMirror Downloader");
    console.log("VERSION:", VERSION);
    console.log("METHOD: wget");
    console.log("======================================");

    for (let i = 0; i < candidates.length; i++) {
        if (await candidate(candidates[i], i + 1)) return;
    }

    throw new Error(`Không tìm thấy NORMAL APK cho ${VERSION}`);
}

main().catch(error => {
    console.error("\n======================================");
    console.error("ERROR:", error.message);
    console.error("======================================");
    process.exit(1);
});
