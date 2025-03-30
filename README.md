# Pico-8 carts list generator

This script checks if each post from BBS contains a Pico-8 cart and saves its ID, title, and author to a file.

## Installation

    git clone https://github.com/bunigost/P8-gencarts.git
    cd P8-gencarts
    chmod +x gen_carts.sh

## Usage

    ./gen_carts.sh
    
Comes with a parallel processing option:

    ./gen_carts.sh --parallel

The default number of jobs is 8, but you can change it by modifying 'NUM_JOBS=' at line 10.

## Known issues

### Issue 1: Special characters
At one point, the script removes all special characters to avoid issues with grep.
Since some titles and author names are made entirely with special characters and to avoid an empty field, the original Title/Author is kept, but it brings duplicate issues.

### Issue 2: Emojis
Some titles and author names contain emojis, making text like "&amp;" appear in cart files. The issue seems to stem from curl, which can't process these characters properly.

### Issue 3 : Posts not containing carts added to carts files
Some posts are wrongfully tagged as cartridges and since the scripts checks for "PICO-8" and "Cartridges" tags, their IDs are added to carts files.
Script should be revamped to check for download link instead of tags.
In the meantime, these IDs are manually added to notcarts.txt.

## Note

- Previously generated files are included in the repo to save you approximately 5 hours and 30 minutes.