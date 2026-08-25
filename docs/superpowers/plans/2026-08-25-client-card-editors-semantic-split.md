# Client Card Editors Semantic Split Plan

1. Add the semantic-part source contract to
   `client_card_save_payload_test.dart`; run it red, then record the clean
   32-test client-card baseline.
2. Replace `client_card_editors.dart` with custom-field, moderation, contact,
   assignment, comment, and family/access parts; format, run focused tests,
   analyze, Sentrux, and commit the structural boundary.
3. Decompose custom-field dispatch and read-only formatting to max CCN `10`;
   run the save-payload/contact tests, analyze, Sentrux, and commit.
4. Decompose blacklist, family-add, and comment target/kind orchestration;
   run the moderation/family/comment behavior gates, analyze, Sentrux, and
   commit.
5. Refresh RepoWise, measure every replacement and the combined deficit, run
   the full Flutter suite, final analyze/diff/Sentrux/change-risk gates, then
   append the verified outcome to the package and global recovery documents.
