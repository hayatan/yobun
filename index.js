// メイン処理
(async () => {
    try {
        const { runScrape } = require('./src/app');
        await runScrape();
    } catch (error) {
        console.error('スクレイピング処理中にエラーが発生しました:', error);
    }
})();
