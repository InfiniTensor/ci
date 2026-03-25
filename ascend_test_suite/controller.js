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

count = 0;

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

app.post("/rank/:node", upload.single("file"), (req, res) => {
    console.log(`Saved rank table: ${req.params.node}.json`);

    console.log(`AAAAA: ${req.params}`);
    console.log(`BBBBB: ${req}`);
    
    res.json({ status: "ok" });

    count++;

    if (count === WORLD_SIZE) {
        // merge();
        process.exit(0);
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
