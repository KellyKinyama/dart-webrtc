// const isDigits = "/^\d+$/";
num stringToIntParser(String input){
  // if(!isDigits.test(input)){
  //   throw new Error(`"${input}" is not an integer.`);
  // }
  return int.parse(input);
}