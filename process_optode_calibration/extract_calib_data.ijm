roiManager("Select", 0);
for (i = 1; i <= nSlices; i++) {
    setSlice(i);
    run("Measure");
}