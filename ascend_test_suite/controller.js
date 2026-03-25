const express = require("express");
const multer = require("multer");
const fs = require("fs");
const { spawn } = require("child_process");
const path = require("path");
const app = express();
const ranks = {};

const port = parseInt(process.argv[2], 10);
const WORLD_SIZE = parseInt(process.argv[3], 10);

const RANK_DIR = path.join(__dirname, "ranks");
// const RANK_DIR = "/CI_Workspace/ranks";
fs.mkdirSync(RANK_DIR, { recursive: true });

let count = 0;

const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        cb(null, RANK_DIR);
    },
    filename: (req, file, cb) => {
        const node = req.params.node;
        cb(null, `${node}.json`);
    }
});

const upload = multer({ storage });

app.post("/rank/:node", upload.single("file"), async (req, res) => {
    try {
        if (!req.file || !req.file.path) {
            res.status(400).json({ status: "error", message: "Missing uploaded file" });
            return;
        }

        console.log(`Saved rank table: ${req.params.node}.json`);

        // Debug: print the uploaded file content.
        // Limit output size to avoid flooding logs with huge payloads.
        const maxBytes = parseInt(process.env.RANK_PRINT_MAX_BYTES || "1048576", 10); // 1 MiB default
        const buf = await fs.promises.readFile(req.file.path);
        const truncated = buf.length > maxBytes;
        const printable = truncated
            ? `${buf.slice(0, maxBytes).toString("utf8")}\n...[truncated](${buf.length} bytes)`
            : buf.toString("utf8");

        console.log(`[rank file content] node=${req.params.node} path=${req.file.path}`);
        console.log(printable);

        res.json({ status: "ok" });

        count++;
        if (count === WORLD_SIZE) {
            // merge();
            // Ensure logs/response are flushed before exiting.
            res.on("finish", () => process.exit(0));
        }
    } catch (err) {
        console.error("Failed to handle /rank upload:", err);
        res.status(500).json({ status: "error", message: err && err.message ? err.message : String(err) });
    }
});

function merge() {
    mergeRankTables(
        ["/tmp/nodeA.json", "/tmp/nodeB.json"],
        err => {
            if (err) {
                console.error(err.message);
            } else {
                console.log("Merged rank_table ready");
            }
        }
    );
}

function mergeRankTables(files) {
    const script = "merge_hccl.py";
    const args = [
        script,
        ...files
    ];

    const proc = spawn("python3", args);

    proc.stdout.on("data", data => {
        console.log(`[merge_hccl stdout] ${data}`);
    });

    proc.stderr.on("data", data => {
        console.error(`[merge_hccl stderr] ${data}`);
    });

    proc.on("close", code => {
        if (code !== 0) {
            console.error("merge failed");
            process.exit(1);
        } else {
            console.log("merge done, exiting controller");
            process.exit(0);
        }
    });
}

app.listen(port, () => {
    console.log(`Controller listening on port ${port}`);
});
